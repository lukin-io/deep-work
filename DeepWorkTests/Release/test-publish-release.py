#!/usr/bin/env python3
"""Publication regression tests with real isolated Git and simulated GitHub.

These cases prove CLI orchestration and fail-closed behavior, not a live release,
macOS archive integrity, signing, or GitHub availability. Native packaging has
its own tests and verify-release.sh; the workflow downloads and verifies uploads.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[2] / "scripts/publish-release.sh"
REAL_GIT = shutil.which("git")
TAG = "v0.1.0-preview.1"
REPOSITORY = "lukin-io/deep-work"
TOKEN = "fixture-token-must-never-be-printed"

MOCK_GH = r'''#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
args = sys.argv[1:]
root = pathlib.Path(os.environ['TEST_STATE'])
with (root / 'events.jsonl').open('a') as stream:
    stream.write(json.dumps(['gh'] + args) + '\n')
state_file = root / 'release.json'
state = json.loads(state_file.read_text()) if state_file.exists() else {}
def save(): state_file.write_text(json.dumps(state))
def fail(message): print(message, file=sys.stderr); sys.exit(1)
def option(name): return args[args.index(name) + 1]
if args[0] == 'api':
    if os.environ.get('TEST_LIST_FAIL'): fail('GitHub unavailable')
    print(os.environ.get('TEST_EXISTING_TAG', ''))
elif args[:2] == ['release', 'create']:
    assert '--verify-tag' in args and '--draft' in args and '--prerelease' in args and '--latest=false' in args
    assert option('--repo') == 'lukin-io/deep-work'
    assert pathlib.Path(option('--notes-file')).is_file()
    state = dict(id='release-101', isDraft=True, isPrerelease=True, tagName=args[2], views=0)
    if os.environ.get('TEST_BAD_CREATED_STATE'): state['isDraft'] = False
    save()
    (root / 'uploaded').mkdir()
    for filename in args[3:args.index('--repo')]:
        shutil.copyfile(filename, root / 'uploaded' / pathlib.Path(filename).name)
    if os.environ.get('TEST_CREATE_FAIL'): fail('Upload interrupted after creating draft')
    print('https://github.com/lukin-io/deep-work/releases/tag/' + args[2])
elif args[:2] == ['release', 'view']:
    state['views'] += 1
    if state['views'] > 1 and os.environ.get('TEST_DRAFT_CHANGED'): state['id'] = 'some-other-release'
    if state['views'] > 2 and os.environ.get('TEST_PUBLISHED_STATE_BAD'): state['isPrerelease'] = False
    save()
    print(json.dumps({key: state[key] for key in ('id', 'isDraft', 'isPrerelease', 'tagName')}))
elif args[:2] == ['release', 'download']:
    if os.environ.get('TEST_DOWNLOAD_FAIL'): fail('Download interrupted')
    destination = pathlib.Path(option('--dir'))
    for asset in (root / 'uploaded').iterdir():
        if os.environ.get('TEST_MISSING_DOWNLOAD') == asset.name: continue
        shutil.copyfile(asset, destination / asset.name)
        if os.environ.get('TEST_CORRUPT_DOWNLOAD') == asset.name:
            (destination / asset.name).write_bytes(b'corrupted remote asset')
elif args[:2] == ['release', 'edit']:
    assert state['isDraft'] and '--draft=false' in args and '--prerelease' in args and '--latest=false' in args
    if os.environ.get('TEST_PUBLISH_FAIL'): fail('Publishing failed')
    state['isDraft'] = False
    save()
else:
    fail('Unexpected gh operation: ' + repr(args))
'''

MOCK_GIT = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
if args and args[0] == 'fetch':
    root = pathlib.Path(os.environ['TEST_STATE'])
    with (root / 'events.jsonl').open('a') as stream:
        stream.write(json.dumps(['git'] + args) + '\n')
    counter = root / 'main-fetch-count'
    count = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(count))
    if os.environ.get('TEST_MAIN_FETCH_FAIL'): sys.exit(128)
    if os.environ.get('TEST_MAIN_REF_MISSING'): sys.exit(0)
    commit = os.environ.get('TEST_MAIN_COMMIT', os.environ['GITHUB_SHA'])
    if count > 1 and os.environ.get('TEST_MAIN_CHANGED'):
        commit = os.environ['TEST_MAIN_CHANGED']
    os.execv(os.environ['TEST_REAL_GIT'], [os.environ['TEST_REAL_GIT'], 'update-ref',
                                        'refs/remotes/origin/main', commit])
if args and args[0] == 'ls-remote':
    root = pathlib.Path(os.environ['TEST_STATE'])
    with (root / 'events.jsonl').open('a') as stream:
        stream.write(json.dumps(['git'] + args) + '\n')
    counter = root / 'remote-count'
    count = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(count))
    if os.environ.get('TEST_REMOTE_MISSING'): sys.exit(2)
    if os.environ.get('TEST_REMOTE_FAIL'): sys.exit(128)
    sha = os.environ.get('TEST_REMOTE_SHA', os.environ['GITHUB_SHA'])
    if count > 1 and os.environ.get('TEST_REMOTE_CHANGED'): sha = '0' * 40
    ref = args[-2]
    if os.environ.get('TEST_LIGHTWEIGHT'):
        print(sha + '\t' + ref)
    else:
        print(os.environ.get('TEST_REMOTE_TAG_OBJECT', os.environ['TEST_TAG_OBJECT']) + '\t' + ref)
        print(sha + '\t' + ref + '^{}')
    sys.exit(0)
os.execv(os.environ['TEST_REAL_GIT'], [os.environ['TEST_REAL_GIT']] + args)
'''

MOCK_CURL = r'''#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
args = sys.argv[1:]
root = pathlib.Path(os.environ['TEST_STATE'])
with (root / 'events.jsonl').open('a') as stream:
    stream.write(json.dumps(['curl'] + args) + '\n')
assert 'GH_TOKEN' not in os.environ and 'GITHUB_TOKEN' not in os.environ
assert args[0] == '--disable' and '--fail' in args and '--location' in args
assert args[-1].startswith('https://github.com/lukin-io/deep-work/releases/download/v0.1.0-preview.1/')
assert not json.loads((root / 'release.json').read_text())['isDraft']
if os.environ.get('TEST_PUBLIC_DOWNLOAD_FAIL'):
    print('Public download unavailable', file=sys.stderr)
    sys.exit(1)
asset = args[-1].rsplit('/', 1)[1]
destination = pathlib.Path(args[args.index('--output') + 1])
shutil.copyfile(root / 'uploaded' / asset, destination)
if os.environ.get('TEST_CORRUPT_PUBLIC_DOWNLOAD') == asset:
    destination.write_bytes(b'corrupt public download')
'''

MOCK_VERIFIER = r'''#!/usr/bin/env python3
import hashlib, json, os, pathlib, sys
root = pathlib.Path(os.environ['TEST_STATE'])
with (root / 'events.jsonl').open('a') as stream:
    stream.write(json.dumps(['verify'] + sys.argv[1:]) + '\n')
calls = root / 'verify-count'
count = int(calls.read_text()) + 1 if calls.exists() else 1
calls.write_text(str(count))
if os.environ.get('TEST_VERIFY_FAIL') or (count > 1 and os.environ.get('TEST_VERIFY_DOWNLOAD_FAIL')):
    raise SystemExit('Native verifier rejected archive')
directory, tag, commit = sys.argv[1:]
directory = pathlib.Path(directory)
metadata = json.loads((directory / 'release-metadata.json').read_text())
assert metadata['tag'] == tag and metadata['commit'] == commit
for line in (directory / 'SHA256SUMS').read_text().splitlines():
    digest, filename = line.split('  ', 1)
    assert hashlib.sha256((directory / filename).read_bytes()).hexdigest() == digest
'''


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="deep-work-publication-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.state = self.root / "state"
        self.state.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        (self.repo / "scripts").mkdir()
        shutil.copyfile(SOURCE, self.repo / "scripts/publish-release.sh")
        (self.repo / "scripts/publish-release.sh").chmod(0o755)
        self.executable(self.bin / "gh", MOCK_GH)
        self.executable(self.bin / "git", MOCK_GIT)
        self.executable(self.bin / "curl", MOCK_CURL)
        self.executable(self.repo / "scripts/verify-release.sh", MOCK_VERIFIER)
        (self.repo / "docs/releases").mkdir(parents=True)
        (self.repo / f"docs/releases/{TAG}.md").write_text("Preview. Ad hoc, not notarized.\n")
        (self.repo / ".gitignore").write_text(".build/\n")
        self.git("init", "-q")
        self.git("config", "user.email", "release-tests@example.invalid")
        self.git("config", "user.name", "Release Test Fixture")
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "tag.gpgsign", "false")
        self.git("remote", "add", "origin", f"https://github.com/{REPOSITORY}.git")
        self.git("add", ".")
        self.git("commit", "-qm", "Fixture")
        self.commit = self.git("rev-parse", "HEAD").strip()
        self.git("tag", "-a", TAG, "-m", "Preview fixture")
        self.archive = f"Deep-Work-{TAG}-macOS-arm64.zip"
        self.assets = [self.archive, "SHA256SUMS", "release-metadata.json"]
        self.artifacts = self.repo / f".build/releases/{TAG}"
        self.artifacts.mkdir(parents=True)
        (self.artifacts / self.archive).write_bytes(b"Mock native archive; not distribution bytes")
        (self.artifacts / "release-metadata.json").write_text(json.dumps(dict(tag=TAG, commit=self.commit)))
        checksums = [f"{hashlib.sha256((self.artifacts / name).read_bytes()).hexdigest()}  {name}" for name in (self.archive, "release-metadata.json")]
        (self.artifacts / "SHA256SUMS").write_text("\n".join(checksums) + "\n")
        # Never inherit a runner's real token, repository, event, or Git overrides.
        self.environment = {key: value for key, value in os.environ.items()
                            if not key.startswith(("GH_", "GITHUB_", "GIT_", "TEST_"))}
        self.environment.update(PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                                TEST_STATE=str(self.state), TEST_REAL_GIT=REAL_GIT,
                                TEST_TAG_OBJECT=self.git("rev-parse", f"refs/tags/{TAG}").strip(),
                                GITHUB_ACTIONS="true", GITHUB_EVENT_NAME="push",
                                GITHUB_REF=f"refs/tags/{TAG}", GITHUB_SHA=self.commit,
                                GITHUB_REPOSITORY=REPOSITORY, GH_TOKEN=TOKEN)

    @staticmethod
    def executable(path, content):
        path.write_text(content)
        path.chmod(0o755)

    def git(self, *args):
        # User Git signing, hooks, templates and runner overrides are irrelevant
        # to this disposable repository and must not affect its fixtures.
        environment = {key: value for key, value in os.environ.items()
                       if not key.startswith("GIT_")}
        environment.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                           GIT_TEMPLATE_DIR="", GIT_TERMINAL_PROMPT="0")
        result = subprocess.run([REAL_GIT, *args], cwd=self.repo, env=environment,
                                text=True, capture_output=True, check=True)
        return result.stdout

    def run_publication(self, expected_success=False, tag=TAG, **overrides):
        environment = dict(self.environment, **overrides)
        result = subprocess.run(["bash", "scripts/publish-release.sh", tag], cwd=self.repo,
                                env=environment, text=True, capture_output=True)
        self.assertEqual(result.returncode == 0, expected_success, result.stdout + result.stderr)
        self.assertNotIn(TOKEN, result.stdout + result.stderr)
        for event in self.events():
            self.assertNotIn("--clobber", event)
            self.assertNotIn("--force", event)
            self.assertNotIn("delete", event)
            self.assertNotIn("push", event)
        return result

    def events(self):
        file = self.state / "events.jsonl"
        return [json.loads(line) for line in file.read_text().splitlines()] if file.exists() else []

    def release_state(self):
        file = self.state / "release.json"
        return json.loads(file.read_text()) if file.exists() else None

    def assert_no_creation(self):
        self.assertIsNone(self.release_state())
        self.assertFalse(any(event[:3] == ["gh", "release", "edit"] for event in self.events()))

    def assert_unpublished_draft(self):
        self.assertTrue(self.release_state()["isDraft"])
        self.assertFalse(any(event[:3] == ["gh", "release", "edit"] for event in self.events()))

    def test_success_verifies_downloads_before_publishing_annotated_tag(self):
        self.run_publication(expected_success=True)
        events = self.events()
        self.assertFalse(self.release_state()["isDraft"])
        self.assertEqual(sum(event[0] == "verify" for event in events), 3)
        self.assertEqual(sum(event[:2] == ["git", "ls-remote"] for event in events), 2)
        self.assertEqual(sum(event[:2] == ["git", "fetch"] for event in events), 2)
        self.assertEqual(sum(event[0] == "curl" for event in events), 3)
        self.assertEqual(events[-1][0], "verify")
        publication_index = next(index for index, event in enumerate(events) if event[:3] == ["gh", "release", "edit"])
        public_index = next(index for index, event in enumerate(events) if event[0] == "curl")
        self.assertEqual(sum(event[0] == "verify" for event in events[:publication_index]), 2)
        self.assertTrue(any(event[:3] == ["gh", "release", "download"] for event in events[:publication_index]))
        self.assertLess(publication_index, public_index)
        self.assertEqual(sorted(file.name for file in (self.state / "uploaded").iterdir()), sorted(self.assets))

    def test_release_commit_can_be_an_ancestor_of_main(self):
        self.git("commit", "--allow-empty", "-qm", "Later merged work")
        main = self.git("rev-parse", "HEAD").strip()
        self.git("checkout", "--detach", self.commit)
        self.run_publication(expected_success=True, TEST_MAIN_COMMIT=main)

    def test_rejects_release_commit_outside_main(self):
        other = self.git("commit-tree", "HEAD^{tree}", "-m", "Unrelated main").strip()
        result = self.run_publication(TEST_MAIN_COMMIT=other)
        self.assertIn("must already belong to origin/main", result.stderr)
        self.assert_no_creation()

    def test_main_refresh_failure_does_not_trust_a_stale_ref(self):
        self.git("update-ref", "refs/remotes/origin/main", self.commit)
        result = self.run_publication(TEST_MAIN_FETCH_FAIL="1")
        self.assertIn("could not refresh origin/main", result.stderr)
        self.assert_no_creation()

    def test_missing_main_ref_prevents_publication(self):
        result = self.run_publication(TEST_MAIN_REF_MISSING="1")
        self.assertIn("origin/main does not resolve", result.stderr)
        self.assert_no_creation()

    def test_main_history_changed_during_upload_retains_draft(self):
        other = self.git("commit-tree", "HEAD^{tree}", "-m", "Rewritten main").strip()
        result = self.run_publication(TEST_MAIN_CHANGED=other)
        self.assertIn("must already belong to origin/main", result.stderr)
        self.assert_unpublished_draft()

    def test_rejects_local_lightweight_tag(self):
        self.git("tag", "-d", TAG)
        self.git("tag", TAG)
        self.run_publication()
        self.assert_no_creation()

    def test_rejects_remote_lightweight_tag(self):
        self.run_publication(TEST_LIGHTWEIGHT="1")
        self.assert_no_creation()

    def test_rejects_remote_tag_recreated_at_same_commit(self):
        self.run_publication(TEST_REMOTE_TAG_OBJECT="0" * 40)
        self.assert_no_creation()

    def test_requires_tagged_ci_context_and_token(self):
        for key, value in (("GITHUB_ACTIONS", ""), ("GITHUB_EVENT_NAME", "pull_request"),
                           ("GITHUB_REF", "refs/heads/main"), ("GITHUB_REPOSITORY", "someone/fork"),
                           ("GITHUB_SHA", "0" * 40), ("GH_TOKEN", "")):
            with self.subTest(key=key):
                self.run_publication(**{key: value})
                self.assert_no_creation()

    def test_rejects_stable_malformed_and_zero_preview_tags(self):
        for tag in ("v1.0.0", "v01.0.0-preview.1", "v0.1.0-preview.0", "../preview", ""):
            with self.subTest(tag=tag):
                self.run_publication(tag=tag)
                self.assert_no_creation()

    def test_rejects_wrong_origin(self):
        self.git("remote", "set-url", "origin", "https://github.com/someone/fork.git")
        self.run_publication()
        self.assert_no_creation()

    def test_rejects_missing_local_tag(self):
        self.git("tag", "-d", TAG)
        self.run_publication()
        self.assert_no_creation()

    def test_rejects_local_tag_at_another_commit(self):
        self.git("commit", "--allow-empty", "-qm", "Another commit")
        result = self.run_publication(GITHUB_SHA=self.git("rev-parse", "HEAD").strip())
        self.assertIn("local tag does not point to HEAD", result.stderr)
        self.assert_no_creation()

    def test_rejects_missing_changed_or_unavailable_remote_tag(self):
        for variable, value in (("TEST_REMOTE_MISSING", "1"), ("TEST_REMOTE_FAIL", "1"), ("TEST_REMOTE_SHA", "0" * 40)):
            with self.subTest(variable=variable):
                self.run_publication(**{variable: value})
                self.assert_no_creation()

    def test_rejects_dirty_checkout(self):
        (self.repo / f"docs/releases/{TAG}.md").write_text("Unreviewed notes")
        self.run_publication()
        self.assert_no_creation()

    def test_rejects_untracked_source(self):
        (self.repo / "unreviewed.swift").write_text("// Not part of the tag")
        self.run_publication()
        self.assert_no_creation()

    def test_rejects_missing_release_notes(self):
        notes = self.repo / f"docs/releases/{TAG}.md"
        notes.unlink()
        self.git("add", "-u")
        self.git("commit", "-qm", "Fixture without notes")
        self.git("tag", "-d", TAG)
        self.git("tag", "-a", TAG, "-m", "Preview without notes")
        result = self.run_publication(GITHUB_SHA=self.git("rev-parse", "HEAD").strip(),
                                      TEST_TAG_OBJECT=self.git("rev-parse", f"refs/tags/{TAG}").strip())
        self.assertIn("checked-in release notes are required", result.stderr)
        self.assert_no_creation()

    def test_requires_all_three_assets(self):
        for asset in self.assets:
            with self.subTest(asset=asset):
                path = self.artifacts / asset
                data = path.read_bytes()
                path.unlink()
                self.run_publication()
                self.assert_no_creation()
                path.write_bytes(data)

    def test_rejects_symlinked_asset(self):
        path = self.artifacts / "release-metadata.json"
        replacement = self.root / "metadata.json"
        path.rename(replacement)
        path.symlink_to(replacement)
        self.run_publication()
        self.assert_no_creation()

    def test_verifier_must_accept_local_artifacts(self):
        self.run_publication(TEST_VERIFY_FAIL="1")
        self.assert_no_creation()

    def test_rejects_metadata_from_another_commit(self):
        (self.artifacts / "release-metadata.json").write_text(json.dumps(dict(tag=TAG, commit="0" * 40)))
        self.run_publication()
        self.assert_no_creation()

    def test_rejects_existing_published_release_or_draft(self):
        self.run_publication(TEST_EXISTING_TAG=TAG)
        self.assert_no_creation()

    def test_release_lookup_error_does_not_imply_absence(self):
        self.run_publication(TEST_LIST_FAIL="1")
        self.assert_no_creation()

    def test_upload_failure_leaves_draft_unpublished(self):
        self.run_publication(TEST_CREATE_FAIL="1")
        self.assert_unpublished_draft()

    def test_unexpected_created_release_is_never_edited(self):
        self.run_publication(TEST_BAD_CREATED_STATE="1")
        self.assertFalse(any(event[:3] == ["gh", "release", "edit"] for event in self.events()))

    def test_download_failure_leaves_draft_unpublished(self):
        self.run_publication(TEST_DOWNLOAD_FAIL="1")
        self.assert_unpublished_draft()

    def test_corrupt_download_leaves_draft_unpublished(self):
        self.run_publication(TEST_CORRUPT_DOWNLOAD=self.archive)
        self.assert_unpublished_draft()

    def test_corrupt_checksum_download_leaves_draft_unpublished(self):
        self.run_publication(TEST_CORRUPT_DOWNLOAD="SHA256SUMS")
        self.assert_unpublished_draft()

    def test_corrupt_metadata_download_leaves_draft_unpublished(self):
        self.run_publication(TEST_CORRUPT_DOWNLOAD="release-metadata.json")
        self.assert_unpublished_draft()

    def test_missing_download_leaves_draft_unpublished(self):
        self.run_publication(TEST_MISSING_DOWNLOAD="release-metadata.json")
        self.assert_unpublished_draft()

    def test_downloaded_bundle_verification_failure_leaves_draft(self):
        self.run_publication(TEST_VERIFY_DOWNLOAD_FAIL="1")
        self.assert_unpublished_draft()

    def test_tag_moved_during_upload_does_not_publish(self):
        self.run_publication(TEST_REMOTE_CHANGED="1")
        self.assert_unpublished_draft()

    def test_changed_draft_is_never_overwritten(self):
        self.run_publication(TEST_DRAFT_CHANGED="1")
        self.assert_unpublished_draft()

    def test_publish_error_preserves_draft_without_retrying(self):
        result = self.run_publication(TEST_PUBLISH_FAIL="1")
        self.assertTrue(self.release_state()["isDraft"])
        self.assertEqual(sum(event[:3] == ["gh", "release", "edit"] for event in self.events()), 1)
        self.assertIn("did not confirm publication", result.stderr)

    def test_public_download_failure_reports_published_but_unverified(self):
        result = self.run_publication(TEST_PUBLIC_DOWNLOAD_FAIL="1")
        self.assertFalse(self.release_state()["isDraft"])
        self.assertIn("release was published, but public download verification failed", result.stderr)

    def test_corrupt_public_download_reports_published_but_unverified(self):
        result = self.run_publication(TEST_CORRUPT_PUBLIC_DOWNLOAD=self.archive)
        self.assertFalse(self.release_state()["isDraft"])
        self.assertIn("release was published, but public download verification failed", result.stderr)

    def test_published_state_mismatch_reports_published_but_unverified(self):
        result = self.run_publication(TEST_PUBLISHED_STATE_BAD="1")
        self.assertFalse(self.release_state()["isDraft"])
        self.assertIn("release was published, but public download verification failed", result.stderr)
        self.assertFalse(any(event[0] == "curl" for event in self.events()))


if __name__ == "__main__":
    unittest.main(verbosity=2)
