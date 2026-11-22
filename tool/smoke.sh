#!/usr/bin/env bash
# Runs inside the Android emulator: install, launch, collect logs/screenshots, probe the web hub.
PKG=dev.carlospeter.pocketserver
mkdir -p smoke
adb install -r apk/PocketServer-android.apk || { echo "install failed" > smoke/result.txt; exit 1; }
adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS || true
adb logcat -c
adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1
sleep 8
adb exec-out screencap -p > smoke/screen_splash.png
sleep 22
adb exec-out screencap -p > smoke/screen_home.png
adb logcat -d > smoke/logcat.txt
adb shell pidof $PKG > smoke/pid.txt || true
adb forward tcp:2011 tcp:2011
curl -s -m 10 -o smoke/hub.html -w "%{http_code}\n" http://127.0.0.1:2011/ > smoke/http.txt || echo "no response" > smoke/http.txt
grep -n "FATAL EXCEPTION" -A25 smoke/logcat.txt | head -80 > smoke/crash.txt
if [ -s smoke/crash.txt ]; then echo CRASH > smoke/result.txt; else echo OK > smoke/result.txt; fi
cat smoke/result.txt smoke/http.txt smoke/pid.txt
echo "=== CRASH TRACE ==="
cat smoke/crash.txt
echo "=== FLUTTER / RUNTIME LOG ==="
grep -E "AndroidRuntime|flutter|FATAL|Exception|Error|dev.carlospeter" smoke/logcat.txt | grep -v "Choreographer" | tail -120
echo "=== END ==="
