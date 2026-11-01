#!/usr/bin/env bash
# Runs the live ambient test on the emulator **and** grabs the physical
# screen while it runs.
#
# ## Why two channels
#
# The test measures the pixels the engine drew, from inside the app
# (the repaint boundary). This wrapper adds the second, independent
# channel: the pixels the emulator actually shows on its display.
#
# Both have to agree for the evidence to mean anything.
#
# ## Why the grabber has to start first
#
# `flutter drive` builds the app before the test starts, and the build
# takes minutes. The screen grabber therefore runs for the whole session
# and the frames that show the preview are picked out afterwards.
#
# Usage: tools/ambient_live_run.sh [serial]
set -euo pipefail

SERIAL="${1:-emulator-5554}"
ROOT="/Users/roy/Documents/desktopapp/uni-launcher/app"
OUT="${UNI_AMBIENT_OUT:-$ROOT/verification/ambient-live}"
SCREEN_OUT="${UNI_SCREEN_OUT:-/tmp/ambient-screen}"

export PATH="/Users/roy/development/flutter/bin:/opt/homebrew/bin:$PATH"
export ANDROID_HOME=/Users/roy/Documents/desktopapp/toolchain/sdk
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME=/Users/roy/Documents/desktopapp/toolchain/jdk-17.0.20.1+1/Contents/Home
export UNI_SIGNING_STORE="$ROOT/android/uni-debug.keystore"
export UNI_EMULATOR_SERIAL="$SERIAL"
export UNI_AMBIENT_OUT="$OUT"

mkdir -p "$OUT" "$SCREEN_OUT"
rm -f "$SCREEN_OUT"/screen-*.png

# The grabber runs for the whole session: the build is slow, and the
# frames with the preview on screen are found afterwards.
python3 "$ROOT/tool/sample_ambient_screen.py" "$SERIAL" 600 "$SCREEN_OUT" \
  >"$SCREEN_OUT/grab.log" 2>&1 &
GRABBER=$!

# Stop the grabber when the test is done.
trap 'kill $GRABBER 2>/dev/null || true' EXIT

cd "$ROOT"
flutter drive --driver=test_driver/ambient_live_driver.dart \
  --target=integration_test/ambient_live_test.dart -d "$SERIAL"
