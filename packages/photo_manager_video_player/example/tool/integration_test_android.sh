#!/bin/bash
# Runs the playback integration tests on a connected Android emulator.
# `flutter test` reinstalls the app, so photo access is granted as soon as it appears.
# With ARTIFACTS_DIR set, the test output, logcat and the frames of failed
# pixel checks are kept there.
set -eo pipefail
cd "$(dirname "$0")/.."
DEVICE="${1:-emulator-5554}"
(
  for _ in $(seq 1 300); do
    for permission in READ_MEDIA_VIDEO READ_MEDIA_IMAGES READ_EXTERNAL_STORAGE WRITE_EXTERNAL_STORAGE; do
      adb -s "$DEVICE" shell pm grant com.fluttercandies.example "android.permission.$permission" >/dev/null 2>&1 || true
    done
    sleep 2
  done
) &
GRANTS=$!
# The grant loop would otherwise keep the CI step open after the tests end.
trap 'kill $GRANTS 2>/dev/null' EXIT

if [ -z "$ARTIFACTS_DIR" ]; then
  flutter test integration_test/playback_test.dart -d "$DEVICE" --timeout 120s
  exit
fi

mkdir -p "$ARTIFACTS_DIR"
adb -s "$DEVICE" logcat -c || true
# Streamed rather than dumped at the end, so a run killed by a timeout keeps it.
adb -s "$DEVICE" logcat -v threadtime > "$ARTIFACTS_DIR/logcat.txt" 2>&1 &
LOGCAT=$!
# PMVP_DIAG: temporary fd 0 diagnostics for the API 28 green-frame failure.
adb -s "$DEVICE" shell getprop ro.build.fingerprint > "$ARTIFACTS_DIR/fingerprint.txt" 2>&1 || true
(
  seen=
  for _ in $(seq 1 3000); do
    pid=$(adb -s "$DEVICE" shell pidof com.fluttercandies.example 2>/dev/null | tr -d '\r')
    if [ -n "$pid" ] && [ "$pid" != "$seen" ]; then
      seen=$pid
      { echo "== pid $pid at $(date -u +%T.%N)"
        adb -s "$DEVICE" shell run-as com.fluttercandies.example ls -l /proc/$pid/fd 2>&1 | head -8
      } >> "$ARTIFACTS_DIR/app_fds.txt"
    fi
    sleep 0.2
  done
) &
FDS=$!
trap 'kill $GRANTS $LOGCAT $FDS 2>/dev/null' EXIT

status=0
flutter test integration_test/playback_test.dart -d "$DEVICE" --timeout 120s \
  2>&1 | tee "$ARTIFACTS_DIR/flutter_test.log" || status=$?

# Rebuilds each frame printed by `_keepFrame` in playback_test.dart.
awk '{ for (i = 1; i <= NF; i++) if ($i == "PMVP_FRAME") print $(i + 1), $(i + 2), $(i + 3), $(i + 4) }' \
  "$ARTIFACTS_DIR/flutter_test.log" | sort -k1,1 -k2,2n -u |
  awk '{ data[$1] = data[$1] $4; got[$1]++; want[$1] = $3 }
       END { for (name in data) print name, got[name], want[name], data[name] }' |
  while read -r name got want data; do
    if [ "$got" != "$want" ]; then
      echo "frame $name: $got of $want chunks; $name.png is incomplete" >&2
    fi
    echo "$data" | base64 -d > "$ARTIFACTS_DIR/$name.png" || true
  done
exit $status
