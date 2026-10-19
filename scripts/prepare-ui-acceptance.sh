#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
appearance="${1:-system}"
clipboard="${2:-normal}"
width="${3:-}"
case "$appearance" in system|light|dark) ;; *) echo 'Usage: prepare-ui-acceptance.sh [system|light|dark] [normal|clipboard-failure] [width:320-1600]' >&2; exit 1;; esac
case "$clipboard" in normal|clipboard-failure) ;; *) echo 'Expected normal or clipboard-failure.' >&2; exit 1;; esac
if [[ -n "$width" ]] && { [[ ! "$width" =~ ^[0-9]{3,4}$ ]] || (( 10#$width < 320 || 10#$width > 1600 )); }; then
    echo 'Width must be an integer from 320 to 1600.' >&2; exit 1
fi
test -x '.build/Deep Work.app/Contents/MacOS/DeepWork' || { echo 'Run ./scripts/build-app.sh first.' >&2; exit 1; }
# Release ignores the data override. Refuse it before copying or launching
# anything; symbol-stripped Debug binaries also fail closed here.
if ! nm -j '.build/Deep Work.app/Contents/MacOS/DeepWork' | /usr/bin/grep 'DebugAcceptanceOptions' >/dev/null; then
    echo 'Acceptance requires the unstripped Debug build from ./scripts/build-app.sh.' >&2; exit 1
fi
# A new identity and embedded data override make every launch safe, including
# relaunches by UI automation or Finder. This never launches or quits an app.
temporary_root="${TMPDIR:-/tmp}"
fixture="$(mktemp -d "${temporary_root%/}/deep-work-ui.XXXXXX")"
ditto '.build/Deep Work.app' "$fixture/Deep Work Acceptance.app"
python3 - "$fixture" "$appearance" "$clipboard" "$width" <<'PY'
import pathlib, plistlib, sys
root = pathlib.Path(sys.argv[1])
app = root / 'Deep Work Acceptance.app'
info_path = app / 'Contents/Info.plist'
info = plistlib.loads(info_path.read_bytes())
suffix = root.name.rsplit('.', 1)[1]
executable = 'DeepWorkAcceptance' + suffix
(app / 'Contents/MacOS/DeepWork').rename(app / 'Contents/MacOS' / executable)
info['CFBundleExecutable'] = executable
info['CFBundleIdentifier'] = 'app.deepwork.mac.acceptance.' + suffix
info['CFBundleName'] = 'Deep Work Acceptance'
info['CFBundleDisplayName'] = 'Deep Work Acceptance'
info.pop('CFBundleURLTypes', None)
info['LSEnvironment'] = {
    'DEEP_WORK_DATA_DIR': str(root / 'data'),
    'DEEP_WORK_APPEARANCE': sys.argv[2],
    'DEEP_WORK_CLIPBOARD_FAILURE': '1' if sys.argv[3] == 'clipboard-failure' else '0',
    'DEEP_WORK_WINDOW_WIDTH': sys.argv[4],
}
info_path.write_bytes(plistlib.dumps(info))
PY
codesign --force --sign - "$fixture/Deep Work Acceptance.app"
printf '%s\n' "$fixture/Deep Work Acceptance.app"
