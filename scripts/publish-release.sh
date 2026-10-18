#!/bin/bash
# Publish only the verified artifacts produced by the tagged GitHub Actions run.
set +x
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { printf 'Release publication refused: %s\n' "$*" >&2; exit 1; }
[[ $# -ge 1 && $# -le 2 ]] || fail "usage: $0 <tag> [artifact-directory]"
tag="$1"
[[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-preview\.([1-9][0-9]*)$ ]] ||
  fail 'ad hoc builds require a vX.Y.Z-preview.N tag (N starts at 1)'
repository='lukin-io/deep-work'
[[ "${GITHUB_ACTIONS:-}" == true && "${GITHUB_EVENT_NAME:-}" == push ]] ||
  fail 'run this script only from the tagged GitHub Actions push workflow'
[[ "${GITHUB_REPOSITORY:-}" == "$repository" ]] || fail 'unexpected GitHub repository'
[[ "${GITHUB_REF:-}" == "refs/tags/$tag" ]] || fail 'the workflow ref does not match the release tag'
[[ -n "${GH_TOKEN:-}" ]] || fail 'GH_TOKEN must contain the workflow GITHUB_TOKEN'
command -v gh >/dev/null || fail 'GitHub CLI (gh) is required'
command -v python3 >/dev/null || fail 'Python 3 is required'
command -v curl >/dev/null || fail 'curl is required for public download verification'
# All requests use github.com explicitly; never inherit a different CLI host or debug logging.
export GH_HOST=github.com GH_PROMPT_DISABLED=1
unset GH_DEBUG

commit="$(git rev-parse --verify HEAD)"
[[ "${GITHUB_SHA:-}" == "$commit" ]] || fail 'the checkout is not the workflow commit'
[[ -z "$(git status --porcelain)" ]] || fail 'the release checkout must be clean'
local_tag_commit="$(git rev-parse --verify "refs/tags/$tag^{commit}" 2>/dev/null)" || fail 'the local tag is missing'
[[ "$local_tag_commit" == "$commit" ]] || fail 'the local tag does not point to HEAD'
[[ "$(git cat-file -t "refs/tags/$tag")" == tag ]] || fail 'release tags must be annotated'
local_tag_object="$(git rev-parse "refs/tags/$tag")"
case "$(git remote get-url origin)" in
  https://github.com/lukin-io/deep-work|https://github.com/lukin-io/deep-work.git|git@github.com:lukin-io/deep-work.git|ssh://git@github.com/lukin-io/deep-work.git) ;;
  *) fail 'origin must be the lukin-io/deep-work GitHub repository' ;;
esac

verify_remote_tag() {
  local remote_refs remote_commit remote_tag_object
  remote_refs="$(git ls-remote --exit-code origin "refs/tags/$tag" "refs/tags/$tag^{}")" ||
    fail 'could not resolve the existing remote release tag'
  remote_commit="$(printf '%s\n' "$remote_refs" | awk -v ref="refs/tags/$tag" \
    '$2 == ref "^{}" { print $1 }')"
  remote_tag_object="$(printf '%s\n' "$remote_refs" | awk -v ref="refs/tags/$tag" '$2 == ref { print $1 }')"
  [[ "$remote_commit" == "$commit" ]] || fail 'the remote tag does not point to the verified commit'
  [[ "$remote_tag_object" == "$local_tag_object" ]] || fail 'the remote annotated tag differs from the checkout tag'
}
verify_remote_tag

verify_main_ancestry() {
  # Every new release follows the merged main history. Refresh the public ref
  # before checking; stale checkout refs cannot authorize publication.
  git fetch --quiet --no-tags origin refs/heads/main:refs/remotes/origin/main ||
    fail 'could not refresh origin/main for release ancestry verification'
  local main_commit
  main_commit="$(git rev-parse --verify 'refs/remotes/origin/main^{commit}' 2>/dev/null)" ||
    fail 'origin/main does not resolve to a commit'
  git merge-base --is-ancestor "$commit" "$main_commit" ||
    fail 'the release commit must already belong to origin/main'
}
verify_main_ancestry

artifact_directory="${2:-.build/releases/$tag}"
[[ -d "$artifact_directory" ]] || fail 'the artifact directory is missing'
artifact_directory="$(cd "$artifact_directory" && pwd -P)"
archive="Deep-Work-$tag-macOS-arm64.zip"
assets=("$archive" SHA256SUMS release-metadata.json)
for asset in "${assets[@]}"; do
  [[ -f "$artifact_directory/$asset" && ! -L "$artifact_directory/$asset" && -s "$artifact_directory/$asset" ]] ||
    fail "missing or invalid release asset: $asset"
done
notes="docs/releases/$tag.md"
[[ -s "$notes" && ! -L "$notes" ]] || fail 'checked-in release notes are required'
git cat-file -e "HEAD:$notes" 2>/dev/null || fail 'release notes must exist in the tagged commit'
./scripts/verify-release.sh "$artifact_directory" "$tag" "$commit"

# Listing fails closed on authentication/network errors, unlike treating every
# failed `release view` as a 404. It also detects existing unpublished drafts.
existing_tags="$(gh api --paginate "repos/$repository/releases?per_page=100" --jq '.[].tag_name')" ||
  fail 'could not check for existing releases'
if printf '%s\n' "$existing_tags" | grep -Fx "$tag" >/dev/null; then
  fail 'this tag already has a release or draft; never replace its assets'
fi

download_directory="$(mktemp -d "${TMPDIR:-/tmp}/deep-work-release.XXXXXX")"
creation_started=false
publication_started=false
published=false
cleanup() {
  local result=$?
  rm -rf "$download_directory"
  if [[ $result -ne 0 && "$published" == true ]]; then
    printf 'The release was published, but public download verification failed. Inspect GitHub; no release or asset was replaced or removed.\n' >&2
  elif [[ $result -ne 0 && "$publication_started" == true ]]; then
    printf 'GitHub did not confirm publication. Inspect the release state before retrying; no automatic replacement was attempted.\n' >&2
  elif [[ $result -ne 0 && "$creation_started" == true ]]; then
    printf 'Publication stopped before publishing. Any created draft was retained; inspect GitHub before choosing a new tag.\n' >&2
  fi
  exit "$result"
}
trap cleanup EXIT
creation_started=true
gh release create "$tag" \
  "$artifact_directory/$archive" "$artifact_directory/SHA256SUMS" "$artifact_directory/release-metadata.json" \
  --repo "$repository" --verify-tag --draft --prerelease --latest=false \
  --title "Deep Work $tag" --notes-file "$notes"

gh release view "$tag" --repo "$repository" --json id,isDraft,isPrerelease,tagName > "$download_directory/created.json"
python3 - "$download_directory/created.json" "$tag" <<'PY'
import json, sys
release = json.load(open(sys.argv[1]))
if not release.get('id') or release.get('tagName') != sys.argv[2] or release.get('isDraft') is not True or release.get('isPrerelease') is not True:
    raise SystemExit('Created release is not the expected unpublished prerelease')
PY
mkdir "$download_directory/assets"
gh release download "$tag" --repo "$repository" --dir "$download_directory/assets" \
  --pattern "$archive" --pattern SHA256SUMS --pattern release-metadata.json
for asset in "${assets[@]}"; do
  cmp -s "$artifact_directory/$asset" "$download_directory/assets/$asset" ||
    fail "downloaded asset differs from the verified build: $asset"
done
./scripts/verify-release.sh "$download_directory/assets" "$tag" "$commit"

# Recheck both identities immediately before the only publication operation.
verify_remote_tag
verify_main_ancestry
gh release view "$tag" --repo "$repository" --json id,isDraft,isPrerelease,tagName > "$download_directory/current.json"
python3 - "$download_directory/created.json" "$download_directory/current.json" <<'PY'
import json, sys
if json.load(open(sys.argv[1])) != json.load(open(sys.argv[2])):
    raise SystemExit('The draft changed during verification; inspect it without overwriting it')
PY
publication_started=true
gh release edit "$tag" --repo "$repository" --draft=false --prerelease --latest=false
published=true
gh release view "$tag" --repo "$repository" --json id,isDraft,isPrerelease,tagName > "$download_directory/published.json"
python3 - "$download_directory/created.json" "$download_directory/published.json" <<'PY'
import json, sys
expected = json.load(open(sys.argv[1]))
expected['isDraft'] = False
if json.load(open(sys.argv[2])) != expected:
    raise SystemExit('GitHub did not report the expected published prerelease')
PY
mkdir "$download_directory/public"
for asset in "${assets[@]}"; do
  # This repository is public. No authorization header, CLI token, or curlrc is
  # used: these are the same browser-download URLs that users receive.
  env -u GH_TOKEN -u GITHUB_TOKEN curl --disable --fail --location --silent --show-error \
    --retry 3 --max-time 60 --proto '=https' --proto-redir '=https' \
    --output "$download_directory/public/$asset" \
    "https://github.com/$repository/releases/download/$tag/$asset"
  cmp -s "$artifact_directory/$asset" "$download_directory/public/$asset" ||
    fail "public download differs from the verified build: $asset"
done
./scripts/verify-release.sh "$download_directory/public" "$tag" "$commit"
printf 'Published verified prerelease: https://github.com/%s/releases/tag/%s\n' "$repository" "$tag"
