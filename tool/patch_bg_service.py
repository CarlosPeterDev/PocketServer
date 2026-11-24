#!/usr/bin/env python3
"""Adds a "Stop" button to the Android foreground-service notification (flutter_background_service_android).

Tapping it stops the servers and ends the app process. The plugin has no API for notification buttons, so the
Java source in the pub cache is patched before the build (CI only). Idempotent. Usage: tool/patch_bg_service.py"""
import glob, os, sys

pat = os.path.expanduser('~/.pub-cache/hosted/pub.dev/flutter_background_service_android-*/android/src/main/java/'
                         'id/flutter/flutter_background_service/BackgroundService.java')
files = glob.glob(pat)
if not files:
    sys.exit('BackgroundService.java not found in the pub cache: ' + pat)
P = files[0]
s = open(P, encoding='utf-8').read()
if 'PS_STOP_FROM_NOTIFICATION' in s:
    print('already patched'); sys.exit(0)

# 1) the action button on the notification
a1 = "                    .setContentIntent(pi);\n"
assert s.count(a1) == 1, 'notification builder anchor'
s = s.replace(a1, """                    .setContentIntent(pi);

            // PocketServer: "Stop" button that ends the servers and the app process
            Intent psStop = new Intent(this, BackgroundService.class);
            psStop.setAction("PS_STOP_FROM_NOTIFICATION");
            PendingIntent psStopPi = PendingIntent.getService(this, 12, psStop,
                    PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
            boolean psAr = "ar".equals(java.util.Locale.getDefault().getLanguage());
            mBuilder.addAction(0, psAr ? "\\u0625\\u064a\\u0642\\u0627\\u0641" : "Stop", psStopPi);
""", 1)

# 2) handle it
a2 = "    public int onStartCommand(Intent intent, int flags, int startId) {\n"
assert s.count(a2) == 1, 'onStartCommand anchor'
s = s.replace(a2, a2 + """        if (intent != null && "PS_STOP_FROM_NOTIFICATION".equals(intent.getAction())) {
            isManuallyStopped = true;
            WatchdogReceiver.remove(this);
            config.setManuallyStopped(true);
            stopForeground(true);
            stopSelf();
            new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
                @Override
                public void run() {
                    android.os.Process.killProcess(android.os.Process.myPid());
                }
            }, 400);
            return START_NOT_STICKY;
        }
""", 1)
open(P, 'w', encoding='utf-8').write(s)
print('patched', P)
