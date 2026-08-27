#!/usr/bin/env bash
set -euo pipefail

previous_apk="${1:?previous APK path is required}"
candidate_apk="${2:?candidate APK path is required}"
: "${ANDROID_PACKAGE:?ANDROID_PACKAGE is required}"
: "${ANDROID_ACTIVITY:?ANDROID_ACTIVITY is required}"

for apk in "$previous_apk" "$candidate_apk"; do
  test -f "$apk"
done

adb uninstall "$ANDROID_PACKAGE" >/dev/null 2>&1 || true
adb install "$previous_apk"
adb shell am force-stop "$ANDROID_PACKAGE"
adb shell am start -W -n "$ANDROID_PACKAGE/$ANDROID_ACTIVITY" > android-upgrade-previous-start.txt
sleep 5
adb shell pidof "$ANDROID_PACKAGE" > android-upgrade-previous-pid.txt
test -s android-upgrade-previous-pid.txt

marker_name='quantara-upgrade-retention.txt'
marker_value="upgrade-retention-${RANDOM}-${RANDOM}"
# Run directory creation and redirection inside one remote shell owned by the
# app UID. Splitting `run-as ... sh -c` arguments lets adb's outer shell consume
# the redirection before `run-as`, which writes outside the app sandbox.
adb shell "run-as $ANDROID_PACKAGE sh -c 'mkdir -p files && printf %s $marker_value > files/$marker_name'"
actual_before="$(adb shell run-as "$ANDROID_PACKAGE" cat "files/$marker_name" | tr -d '\r')"
test "$actual_before" = "$marker_value"

adb shell dumpsys package "$ANDROID_PACKAGE" > android-upgrade-before-package.txt
previous_version_code="$(sed -nE 's/.*versionCode=([0-9]+).*/\1/p' android-upgrade-before-package.txt | head -n 1)"
test -n "$previous_version_code"

# `-r` must preserve package data; `-d` is intentionally forbidden so a
# non-monotonic candidate fails rather than hiding an upgrade defect.
adb install -r "$candidate_apk" > android-upgrade-install.txt

adb shell dumpsys package "$ANDROID_PACKAGE" > android-upgrade-after-package.txt
candidate_version_code="$(sed -nE 's/.*versionCode=([0-9]+).*/\1/p' android-upgrade-after-package.txt | head -n 1)"
test -n "$candidate_version_code"
test "$candidate_version_code" -gt "$previous_version_code"

actual_after="$(adb shell run-as "$ANDROID_PACKAGE" cat "files/$marker_name" | tr -d '\r')"
test "$actual_after" = "$marker_value"

adb logcat -c
adb shell am force-stop "$ANDROID_PACKAGE"
adb shell am start -W -n "$ANDROID_PACKAGE/$ANDROID_ACTIVITY" > android-upgrade-candidate-start.txt
sleep 8
adb shell pidof "$ANDROID_PACKAGE" > android-upgrade-candidate-pid.txt
test -s android-upgrade-candidate-pid.txt
sleep 10
adb shell pidof "$ANDROID_PACKAGE" > android-upgrade-candidate-pid-after-settle.txt
test -s android-upgrade-candidate-pid-after-settle.txt
adb logcat -d > android-upgrade-logcat.txt

! grep -Eq "FATAL EXCEPTION|Process: $ANDROID_PACKAGE|Unable to instantiate application|WorkManager is not initialized properly" android-upgrade-logcat.txt
