# PocketServer

File hub for Android, iOS, macOS, Linux and Windows.

- **Web hubs** (default port 2011): browse, upload, share links, users & permissions, clipboards, notes, stars, activity, text editor. Create several, each with its own port.
- **WebDAV servers**: mount as a network drive (Windows, macOS, Linux, Android) with username and password.
- **Login protection**: IPs are blocked for 10 minutes after repeated failed logins (web, FTP, WebDAV).
- **Dashboard**: live traffic, speed chart, storage breakdown, activity.
- **FTP / FTPS servers**: any number, each with name, username, password, port, read-only / anonymous. Plain FTP, explicit FTPS (AUTH TLS), implicit FTPS (self-signed certificate).
- **One shared folder**: every server shares PocketServer's own folder (no storage permission needed). Add files through the web page, FTP or WebDAV.
- **Android** runs servers in a foreground service (type `specialUse`) so they keep running in the background.
- **Languages**: English and Arabic (RTL). First launch follows the phone language (Arabic phone -> Arabic, otherwise English); change it in Settings.
- **First launch** asks for the language and the privacy policy (`assets/privacy.json`, mirrored in `PRIVACY.md` by `tool/gen_privacy_md.py`). Nothing starts before the policy is accepted.
- **Battery**: on Android the app explains why, then shows the system "Allow" box (full APK). The Play build does not declare that restricted permission and opens the battery settings page instead.
- The web page is converted to old-browser JavaScript (`tool/transpile_web_ui.py`) so it also works on smart-TV browsers.
- **Web page in Arabic**: the browser page follows the browser language (Arabic -> right-to-left Arabic) with a round EN/ع button (`tool/web_i18n.py`).
- **Intro slides** (shown once, again from Settings): works without internet, private / not a spy, 3 steps (`assets/intro.json`).
- **Guide**: simple in-app help (what web / FTP / WebDAV are, how to connect over WiFi or hotspot, safety, troubleshooting) in `assets/help.json`.
- Google Play: see `PLAY_STORE.md` for what is ready and what you must still do (own signing key, real AdMob ids).
- AdMob test ads (app-open on the splash, banner on top) on Android and iOS only.

## Android builds
- `PocketServer-android.apk` - one APK for every phone (installs directly).
- `PocketServer-android.aab` - the same app as a bundle for Google Play. Same code and permissions as the APK, so testing the APK tests what Play will publish.

## Build
Windows: `PocketServer-windows-setup.exe` installer (unsigned, SmartScreen may warn) plus a portable zip.

GitHub Actions (`.github/workflows/build.yml`) generates platform folders with `flutter create`, patches them with `tool/patch_platforms.py`, builds all targets and publishes a GitHub Release.
`tool/gen_web_ui.py` regenerates `lib/host/web_ui.dart` from the original Python `files.py`.

AdMob ids in `lib/ads.dart`, the Android manifest and iOS Info.plist (via `tool/patch_platforms.py`) are Google **test** ids: replace them before release.
