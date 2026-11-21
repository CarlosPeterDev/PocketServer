#!/usr/bin/env python3
"""Patches the platform folders created by `flutter create` (run in CI, repo root)."""
import re
import sys
from pathlib import Path

APP = "InfinityShare"
ID = "dev.carlospeter.infinityshare"


def rd(p):
    return Path(p).read_text()


def wr(p, s):
    Path(p).write_text(s)


def insert_before_last(s, closing, text):
    i = s.rfind(closing)
    if i < 0:
        sys.exit(f"cannot find {closing}")
    return s[:i] + text + s[i:]


# ───────────── Android manifest ─────────────
def android_manifest():
    p = "android/app/src/main/AndroidManifest.xml"
    s = rd(p)
    if "xmlns:tools" not in s:
        s = s.replace("<manifest ", '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)
    perms = [
        "INTERNET", "ACCESS_NETWORK_STATE", "ACCESS_WIFI_STATE", "WAKE_LOCK",
        "FOREGROUND_SERVICE", "FOREGROUND_SERVICE_DATA_SYNC", "POST_NOTIFICATIONS",
        "CHANGE_WIFI_MULTICAST_STATE", "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
    ]
    block = "".join(f'    <uses-permission android:name="android.permission.{x}"/>\n' for x in perms)
    s = re.sub(r"(<manifest[^>]*>\s*)", lambda m: m.group(1) + "\n" + block, s, count=1)
    s = re.sub(r'android:label="[^"]*"', f'android:label="{APP}"', s, count=1)
    svc = (
        '        <service android:name="id.flutter.flutter_background_service.BackgroundService"\n'
        '            android:foregroundServiceType="dataSync" android:exported="true"\n'
        '            tools:replace="android:exported,android:foregroundServiceType"/>\n'
    )
    s = insert_before_last(s, "</application>", svc)
    wr(p, s)


# ───────────── Android gradle (kts or groovy) ─────────────
def android_gradle():
    kts = Path("android/app/build.gradle.kts")
    if kts.exists():
        s = kts.read_text()
        s = re.sub(r'applicationId\s*=\s*"[^"]*"', f'applicationId = "{ID}"', s)
        s = re.sub(r'namespace\s*=\s*"[^"]*"', f'namespace = "{ID}"', s)
        s = re.sub(r"minSdk\s*=\s*[^\n]+", "minSdk = 24", s)
        signing = '''    signingConfigs {
        create("release") {
            storeFile = rootProject.file("../signing/infinityshare.jks")
            storePassword = "infinityshare"
            keyAlias = "infinityshare"
            keyPassword = "infinityshare"
        }
    }

'''
        s = s.replace("    buildTypes {", signing + "    buildTypes {", 1)
        s = re.sub(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
                   'signingConfig = signingConfigs.getByName("release")', s)
        if 'getByName("release")' not in s:
            sys.exit("could not patch signing in build.gradle.kts")
        kts.write_text(s)
        return
    g = Path("android/app/build.gradle")
    s = g.read_text()
    s = re.sub(r'applicationId\s+"[^"]*"', f'applicationId "{ID}"', s)
    s = re.sub(r'namespace\s+"[^"]*"', f'namespace "{ID}"', s)
    s = re.sub(r"minSdkVersion\s+[^\n]+", "minSdkVersion 24", s)
    signing = '''    signingConfigs {
        release {
            storeFile rootProject.file("../signing/infinityshare.jks")
            storePassword "infinityshare"
            keyAlias "infinityshare"
            keyPassword "infinityshare"
        }
    }

'''
    s = s.replace("    buildTypes {", signing + "    buildTypes {", 1)
    s = s.replace("signingConfig signingConfigs.debug", "signingConfig signingConfigs.release")
    g.write_text(s)


# ───────────── iOS ─────────────
def ios():
    p = "ios/Runner/Info.plist"
    s = rd(p)
    add = f"""\t<key>NSLocalNetworkUsageDescription</key>
\t<string>{APP} shares your files with other devices on your network.</string>
\t<key>UIFileSharingEnabled</key>
\t<true/>
\t<key>LSSupportsOpeningDocumentsInPlace</key>
\t<true/>
"""
    s = insert_before_last(s, "</dict>", add)
    s = re.sub(r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*", r"\g<1>" + APP, s)
    wr(p, s)


# ───────────── macOS ─────────────
def macos():
    for name in ("DebugProfile", "Release"):
        p = f"macos/Runner/{name}.entitlements"
        s = rd(p)
        add = """\t<key>com.apple.security.network.server</key>
\t<true/>
\t<key>com.apple.security.network.client</key>
\t<true/>
\t<key>com.apple.security.files.user-selected.read-write</key>
\t<true/>
"""
        # avoid duplicate keys (flutter create already adds network.server in DebugProfile)
        lines = add.strip("\n").split("\n")
        out = []
        for i in range(0, len(lines), 2):
            key = re.search(r"<key>(.*)</key>", lines[i]).group(1)
            if key not in s:
                out += lines[i:i + 2]
        if out:
            s = insert_before_last(s, "</dict>", "\n".join(out) + "\n")
        wr(p, s)


if __name__ == "__main__":
    which = set(sys.argv[1:]) or {"android", "ios", "macos"}
    if "android" in which:
        android_manifest()
        android_gradle()
    if "ios" in which:
        ios()
    if "macos" in which:
        macos()
    print("patched:", ", ".join(sorted(which)))
