#!/usr/bin/env bash
set -euo pipefail

apk_path="${1:-apk/app-release.apk}"
: "${ANDROID_PACKAGE:?ANDROID_PACKAGE is required}"
: "${ANDROID_ACTIVITY:?ANDROID_ACTIVITY is required}"

adb install -r "$apk_path"
adb logcat -c
adb shell am force-stop "$ANDROID_PACKAGE"

: > android-start.txt
launched=false
for attempt in 1 2 3; do
  echo "Cold-start attempt $attempt" | tee -a android-start.txt
  set +e
  adb shell am start -W -n "$ANDROID_PACKAGE/$ANDROID_ACTIVITY" >> android-start.txt 2>&1
  start_status=$?
  set -e
  cat android-start.txt
  sleep 8
  if adb shell pidof "$ANDROID_PACKAGE" > android-pid.txt && test -s android-pid.txt; then
    launched=true
    break
  fi
  echo "Start command exited with $start_status and no live process; retrying." | tee -a android-start.txt
  adb shell am force-stop "$ANDROID_PACKAGE" || true
  sleep 3
done

test "$launched" = true
cat android-pid.txt
sleep 15
adb shell pidof "$ANDROID_PACKAGE" > android-pid-after-settle.txt
test -s android-pid-after-settle.txt
adb logcat -d > android-logcat.txt
adb shell dumpsys jobscheduler "$ANDROID_PACKAGE" > android-jobscheduler.txt || true
! grep -Eq "FATAL EXCEPTION|Process: $ANDROID_PACKAGE|Unable to instantiate application|WorkManager is not initialized properly" android-logcat.txt
