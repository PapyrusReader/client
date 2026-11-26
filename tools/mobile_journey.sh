#!/usr/bin/env bash
# Takes the ID of a fresh, disposable English-language emulator or iPhone simulator.
set -euo pipefail
cd "$(dirname "$0")/../app"
device=${1:?Pass a disposable emulator or simulator ID}
shift
args=(--no-label -d "$device"
      --dart-define="JOURNEY_EPUB=$(base64 < patrol_test/fixtures/waypoints.epub | tr -d '\n')"
      --dart-define="JOURNEY_PDF=$(base64 < patrol_test/fixtures/landmarks.pdf | tr -d '\n')"
      --dart-define="JOURNEY_SEED=${JOURNEY_SEED:-42}")
if (( $# )); then
  for target in "$@"; do args+=(--target "$target"); done
elif [[ "${JOURNEY_SUITE:-full}" == navigation ]]; then
  args+=(--target patrol_test/back_navigation_test.dart)
elif [[ "${JOURNEY_SUITE:-full}" == pr ]]; then
  args+=(--exclude patrol_test/reader_gestures_test.dart)
fi
if [[ "$device" == emulator-* ]]; then
  export ANDROID_SERIAL="$device"
  # A freshly booted emulator can report boot completion before Downloads is writable.
  deadline=$((SECONDS + 90))
  until adb -s "$device" shell 'mkdir -p /sdcard/Download && cat > /sdcard/Download/PapyrusJourney.epub' < test/data/book1.epub; do
    if (( SECONDS >= deadline )); then
      echo "Could not stage the EPUB in Downloads on $device" >&2
      exit 1
    fi
    sleep 2
  done
  adb -s "$device" shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
    -d file:///sdcard/Download/PapyrusJourney.epub
  args+=(--flavor direct --dart-define="EMULATOR_MODEL=$(adb -s "$device" shell getprop ro.product.model | tr -d '\r')")
else
  xcrun simctl bootstatus "$device" -b
  groups=$(xcrun simctl get_app_container "$device" com.apple.DocumentsApp groups)
  storage=$(awk -F '\t' '$1 == "group.com.apple.FileProvider.LocalStorage" {print $2}' <<< "$groups")
  [[ -d "$storage" ]]
  mkdir -p "$storage/File Provider Storage"
  cp test/data/book1.epub "$storage/File Provider Storage/PapyrusJourney.epub"
  args+=(--full-isolation --test-server-port 28981 --app-server-port 28982)
fi
# Patrol generates this entrypoint under the test directory.
trap 'rm -f patrol_test/test_bundle.dart' EXIT
patrol test "${args[@]}"
