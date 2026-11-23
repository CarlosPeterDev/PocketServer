#!/usr/bin/env python3
"""Patches the platform folders created by `flutter create` (run in CI, repo root)."""
import re
import sys
from pathlib import Path

APP = "PocketServer"
ID = "dev.carlospeter.pocketserver"


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
        "FOREGROUND_SERVICE", "FOREGROUND_SERVICE_SPECIAL_USE", "POST_NOTIFICATIONS",
        "MANAGE_EXTERNAL_STORAGE", "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
    ]
    block = "".join(f'    <uses-permission android:name="android.permission.{x}"/>\n' for x in perms)
    s = re.sub(r"(<manifest[^>]*>\s*)", lambda m: m.group(1) + "\n" + block, s, count=1)
    s = re.sub(r'android:label="[^"]*"', f'android:label="{APP}"', s, count=1)
    svc = (
        '        <meta-data android:name="com.google.android.gms.ads.APPLICATION_ID"\n'
        '            android:value="ca-app-pub-3940256099942544~3347511713"/>\n'  # AdMob TEST app id
        '        <service android:name="id.flutter.flutter_background_service.BackgroundService"\n'
        '            android:foregroundServiceType="specialUse" android:exported="true"\n'
        '            tools:replace="android:exported,android:foregroundServiceType">\n'
        '            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"\n'
        '                android:value="Local file sharing server (HTTP, FTP, FTPS) that the user starts and stops"/>\n'
        '        </service>\n'
    )
    s = insert_before_last(s, "</application>", svc)
    # Play: no boot start (the plugin adds this receiver + permission by default) and no cloud backup of
    # config.json (it holds the server passwords)
    drop = (
        '    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" tools:node="remove"/>\n'
        '    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" tools:node="remove"/>\n'
    )
    s = re.sub(r"(<manifest[^>]*>\s*)", lambda m: m.group(1) + "\n" + drop, s, count=1)
    s = insert_before_last(s, "</application>",
        '        <receiver android:name="id.flutter.flutter_background_service.BootReceiver" tools:node="remove"/>\n')
    s = s.replace("<application", '<application android:allowBackup="false" tools:replace="android:allowBackup"', 1)
    # Android TV / leanback support
    tv = (
        '    <uses-feature android:name="android.software.leanback" android:required="false"/>\n'
        '    <uses-feature android:name="android.hardware.touchscreen" android:required="false"/>\n'
    )
    s = re.sub(r"(<manifest[^>]*>\s*)", lambda m: m.group(1) + "\n" + tv, s, count=1)
    s = s.replace(
        '<category android:name="android.intent.category.LAUNCHER"/>',
        '<category android:name="android.intent.category.LAUNCHER"/>\n'
        '                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>',
        1,
    )
    wr(p, s)


def strip_all_files():
    """Play Store build: remove the restricted 'all files access' permission."""
    p = "android/app/src/main/AndroidManifest.xml"
    s = rd(p)
    s = re.sub(r'\s*<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>', "", s)
    # Play restricts the battery-optimisation exemption request too (the app then opens the settings page instead)
    s = re.sub(r'\s*<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>', "", s)
    wr(p, s)


# ───────────── Android gradle (kts or groovy) ─────────────
def disable_lint_vital():
    """Some plugin AARs crash Android lint during release builds; lint is not needed for CI."""
    kts = Path("android/build.gradle.kts")
    if kts.exists():
        kts.write_text(kts.read_text() + """
subprojects {
    tasks.configureEach {
        if (name.startsWith("lintVital") || name.startsWith("lintAnalyze")) {
            enabled = false
        }
    }
}
""")
        return
    g = Path("android/build.gradle")
    g.write_text(g.read_text() + """
subprojects {
    tasks.configureEach { t ->
        if (t.name.startsWith("lintVital") || t.name.startsWith("lintAnalyze")) { t.enabled = false }
    }
}
""")


def android_gradle():
    disable_lint_vital()
    kts = Path("android/app/build.gradle.kts")
    if kts.exists():
        s = kts.read_text()
        s = re.sub(r'applicationId\s*=\s*"[^"]*"', f'applicationId = "{ID}"', s)
        s = re.sub(r'namespace\s*=\s*"[^"]*"', f'namespace = "{ID}"', s)
        s = re.sub(r"minSdk\s*=\s*[^\n]+", "minSdk = 24", s)
        signing = '''    signingConfigs {
        create("release") {
            storeFile = rootProject.file("../signing/pocketserver.jks")
            storePassword = "pocketserver"
            keyAlias = "pocketserver"
            keyPassword = "pocketserver"
        }
    }

'''
        s = s.replace("    buildTypes {", signing + "    buildTypes {", 1)
        s = re.sub(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
                   'signingConfig = signingConfigs.getByName("release")', s)
        # R8 strips Room/WorkManager classes (pulled in by the ads SDK) and the app crashes on launch
        s = re.sub(r"(buildTypes\s*\{\s*release\s*\{)", r"\1\n            isMinifyEnabled = false\n            isShrinkResources = false", s, count=1)
        if "isMinifyEnabled = false" not in s:
            sys.exit("could not disable minify in build.gradle.kts")
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
            storeFile rootProject.file("../signing/pocketserver.jks")
            storePassword "pocketserver"
            keyAlias "pocketserver"
            keyPassword "pocketserver"
        }
    }

'''
    s = s.replace("    buildTypes {", signing + "    buildTypes {", 1)
    s = s.replace("signingConfig signingConfigs.debug", "signingConfig signingConfigs.release")
    s = re.sub(r"(buildTypes\s*\{\s*release\s*\{)", r"\1\n            minifyEnabled false\n            shrinkResources false", s, count=1)
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
    add += """\t<key>GADApplicationIdentifier</key>
\t<string>ca-app-pub-3940256099942544~1458002511</string>
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
        # not sandboxed: lets the user share any folder (not distributed through the Mac App Store)
        s = re.sub(r"(<key>com.apple.security.app-sandbox</key>\s*)<true/>", r"\1<false/>", s)
        wr(p, s)


if __name__ == "__main__":
    if sys.argv[1:] == ["strip-allfiles"]:
        strip_all_files()
        print("stripped MANAGE_EXTERNAL_STORAGE + REQUEST_IGNORE_BATTERY_OPTIMIZATIONS")
        sys.exit(0)
    which = set(sys.argv[1:]) or {"android", "ios", "macos"}
    if "android" in which:
        android_manifest()
        android_gradle()
    if "ios" in which:
        ios()
    if "macos" in which:
        macos()
    print("patched:", ", ".join(sorted(which)))
