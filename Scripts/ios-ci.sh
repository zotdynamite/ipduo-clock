#!/usr/bin/env bash
# Build Ipduo Clock for the iOS Simulator on a GitHub-hosted Mac and capture screenshots.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

select_xcode() {
  python3 - <<'PY'
import glob, os, plistlib

def version_key(text):
    parts = []
    for piece in text.split("."):
        digits = ""
        for char in piece:
            if char.isdigit():
                digits += char
            else:
                break
        parts.append(int(digits or "0"))
    return parts

candidates = []
for path in glob.glob("/Applications/Xcode*.app"):
    plist_path = os.path.join(path, "Contents", "Info.plist")
    if not os.path.isfile(plist_path):
        continue
    # Prefer the real bundle over a symlink alias of the same version.
    real = os.path.realpath(path)
    with open(plist_path, "rb") as handle:
        info = plistlib.load(handle)
    version = str(info.get("CFBundleShortVersionString") or "")
    if not version:
        continue
    candidates.append((version_key(version), version, real))

if not candidates:
    raise SystemExit("No Xcode.app found under /Applications")

candidates.sort()
chosen = candidates[-1]
print(chosen[2])
PY
}

XCODE_APP="$(select_xcode)"
echo "Selecting Xcode at $XCODE_APP"
sudo xcode-select -s "$XCODE_APP"
sudo xcodebuild -runFirstLaunch || true

{
  echo "xcode-select: $(xcode-select -p)"
  xcodebuild -version
  echo
  xcodebuild -showsdks
} | tee "$ROOT/ci-toolchain.txt"

echo "Running IpduoClockCore tests"
swift test

python3 - <<'PY' > "$ROOT/ci-destination.txt"
import json, subprocess, sys

raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"])
data = json.loads(raw)

def runtime_version(runtime):
    # com.apple.CoreSimulator.SimRuntime.iOS-27-0
    marker = "iOS-"
    if marker not in runtime:
        return None
    tail = runtime.split(marker, 1)[1]
    parts = []
    for piece in tail.split("-"):
        if piece.isdigit():
            parts.append(int(piece))
        else:
            break
    return tuple(parts) if parts else None

best = None
for runtime, devices in data.get("devices", {}).items():
    version = runtime_version(runtime)
    if not version:
        continue
    for device in devices:
        if not device.get("isAvailable", True):
            continue
        name = device.get("name", "")
        # Landscape regular width needs a Plus / Pro Max class phone.
        if "Pro Max" not in name and "Plus" not in name:
            continue
        rank = (version, 2 if "Pro Max" in name else 1, name)
        if best is None or rank > best[0]:
            best = (rank, device["udid"], name, ".".join(str(part) for part in version))

if best is None:
    print("No Pro Max or Plus iPhone simulator is installed", file=sys.stderr)
    sys.exit(1)

_, udid, name, version = best
print(f"{udid}|{name}|{version}")
PY

IFS='|' read -r UDID DEVICE_NAME DEVICE_OS < "$ROOT/ci-destination.txt"
DEST="platform=iOS Simulator,id=$UDID"
echo "Simulator: $DEVICE_NAME (iOS $DEVICE_OS) $UDID"
{
  echo
  echo "simulator: $DEVICE_NAME"
  echo "simulator-os: $DEVICE_OS"
  echo "simulator-udid: $UDID"
} >> "$ROOT/ci-toolchain.txt"

mkdir -p "$ROOT/screenshots"
rm -rf "$ROOT/TestResults.xcresult"
DERIVED="${RUNNER_TEMP:-/tmp}/IpduoDerived"
rm -rf "$DERIVED"

xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
xcrun simctl erase "$UDID" >/dev/null 2>&1 || true
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl ui "$UDID" appearance dark || true
xcrun simctl status_bar "$UDID" override \
  --time "9:41" \
  --batteryState charged \
  --batteryLevel 100 \
  --wifiBars 3 \
  --cellularMode active \
  --cellularBars 4 || true

set -o pipefail
xcodebuild test \
  -project "$ROOT/IpduoClock.xcodeproj" \
  -scheme IpduoClock \
  -destination "$DEST" \
  -derivedDataPath "$DERIVED" \
  -resultBundlePath "$ROOT/TestResults.xcresult" \
  -only-testing:IpduoClockUITests \
  -parallel-testing-enabled NO \
  CODE_SIGN_STYLE=Manual \
  "CODE_SIGN_IDENTITY=-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  DEVELOPMENT_TEAM="" \
  CODE_SIGN_ENTITLEMENTS="" \
  "TEST_RUNNER_IPDUO_SCREENSHOT_DIR=$ROOT/screenshots" \
  | tee "$ROOT/ci-xcodebuild.log" | (xcbeautify || cat)

echo "Screenshots:"
find "$ROOT/screenshots" -name '*.png' -print | sort

# Attachments inside the xcresult are a second copy if the test runner could not write the directory.
if ! find "$ROOT/screenshots" -name '*.png' | grep -q .; then
  echo "No PNGs written by the test runner; exporting xcresult attachments"
  mkdir -p "$ROOT/screenshots"
  xcrun xcresulttool export attachments \
    --path "$ROOT/TestResults.xcresult" \
    --output-path "$ROOT/screenshots/xcresult-attachments" \
    || true
fi
