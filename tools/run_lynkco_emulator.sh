#!/usr/bin/env bash
# Build the current launcher and install it on the existing persistent 820A AVD.
# Usage: tools/run_lynkco_emulator.sh
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
sdk="${ANDROID_SDK_ROOT:-/data/tools/linkco-android/sdk}"
flutter="${UNI_FLUTTER:-/data/tools/flutter/bin/flutter}"
avd_dir="${UNI_AVD_DIR:-$repo/../simulator/linux-avd}"
serial="emulator-5554"
adb="$sdk/platform-tools/adb"
starter="$avd_dir/start-lynkco-linux.sh"
signing_dir="${UNI_EMULATOR_PLATFORM_KEYS:-/data/tools/linkco-android/ip753-signing}"
expected_avd="Lynkco_820A_persistent"
tmp_dir=""
cleanup() {
  if [[ -n "$tmp_dir" ]]; then
    rm -f "$tmp_dir/key.pem" "$tmp_dir/signing.p12"
    rmdir "$tmp_dir"
  fi
}
trap cleanup EXIT

for executable in "$adb" "$starter" "$flutter"; do
  [[ -x "$executable" ]] || { echo "Missing executable: $executable" >&2; exit 1; }
done
if [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
  echo 'A graphical desktop is required to show the emulator window.' >&2
  exit 1
fi

if "$adb" -s "$serial" get-state >/dev/null 2>&1; then
  avd_name="$("$adb" -s "$serial" emu avd name | tr -d '\r' | head -n 1)"
  [[ "$avd_name" == "$expected_avd" ]] || {
    echo "$serial is $avd_name, not $expected_avd; refusing to install." >&2
    exit 1
  }
  echo "Using running AVD: $avd_name"
else
  echo "Starting $expected_avd with its existing data partition..."
  emulator_log="${TMPDIR:-/tmp}/uni-lynkco-emulator.log"
  if command -v systemd-run >/dev/null && systemctl --user show-environment >/dev/null 2>&1; then
    emulator_unit="uni-lynkco-emulator-$$"
    launch_env=("--setenv=DISPLAY=${DISPLAY:-}" "--setenv=WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}"
      "--setenv=XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-}" "--setenv=XAUTHORITY=${XAUTHORITY:-}"
      "--setenv=ANDROID_SDK_ROOT=$sdk")
    systemd-run --user --quiet --collect --unit="$emulator_unit" --service-type=exec \
      --property="StandardOutput=append:$emulator_log" --property="StandardError=append:$emulator_log" \
      "${launch_env[@]}" "$starter"
  else
    # Detach from the invoking terminal so the emulator survives script exit.
    setsid -f "$starter" >> "$emulator_log" 2>&1 < /dev/null
  fi
fi

if [[ -n "${UNI_EMULATOR_SIGNING_STORE:-}" ]]; then
  signing_store="$UNI_EMULATOR_SIGNING_STORE"
else
  [[ -f "$signing_dir/platform.pk8" && -f "$signing_dir/platform.x509.pem" ]] || {
    echo 'Platform signing files are missing; set UNI_EMULATOR_SIGNING_STORE.' >&2
    exit 1
  }
  umask 077
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/uni-emulator-signing.XXXXXXXX")"
  openssl pkcs8 -inform DER -in "$signing_dir/platform.pk8" -nocrypt -out "$tmp_dir/key.pem"
  openssl pkcs12 -export -inkey "$tmp_dir/key.pem" -in "$signing_dir/platform.x509.pem" \
    -out "$tmp_dir/signing.p12" -name uni-debug -passout pass:android
  signing_store="$tmp_dir/signing.p12"
fi

echo 'Building the current x86_64 release...'
(cd "$repo/app" && UNI_SIGNING_STORE="$signing_store" "$flutter" build apk \
  --release --target-platform android-x64 --no-pub)
apk="$repo/app/build/app/outputs/flutter-apk/app-release.apk"

echo 'Waiting for Android to finish booting...'
deadline=$((SECONDS + 240))
until [[ "$(timeout 5 "$adb" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; do
  if [[ -n "${emulator_unit:-}" ]] && ! systemctl --user is-active --quiet "$emulator_unit"; then
    echo "Emulator stopped; inspect ${TMPDIR:-/tmp}/uni-lynkco-emulator.log" >&2
    exit 1
  fi
  (( SECONDS < deadline )) || { echo 'Emulator boot timed out.' >&2; exit 1; }
  sleep 2
done
avd_name="$("$adb" -s "$serial" emu avd name | tr -d '\r' | head -n 1)"
[[ "$avd_name" == "$expected_avd" ]] || { echo "Unexpected AVD: $avd_name" >&2; exit 1; }

echo 'Installing without clearing application data...'
"$adb" -s "$serial" install -r "$apk"
"$adb" -s "$serial" shell am start -n xyz.i4o.uni.launcher/.MainActivity
echo "Ready: $serial / $expected_avd"
echo "APK: $apk"
