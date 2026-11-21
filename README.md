# PocketServer

File hub for Android, iOS, macOS, Linux and Windows.

- **Web hubs** (default port 2011): browse, upload, share links, users & permissions, clipboards, notes, stars, activity, text editor. Create several, each with its own port and folder.
- **TV mode** at `/tv` on any hub: 10-foot video browser for smart TVs and Android TV (D-pad, Liked, Recently added).
- **FTP / FTPS servers**: any number, each with name, username, password, port, read-only / anonymous, and one or more folders (several folders are merged as top-level directories). Plain FTP, explicit FTPS (AUTH TLS), implicit FTPS (self-signed certificate).
- **Folders (spaces)**: pick folders from storage and assign them to servers.
- **Android** runs servers in a foreground service (type `specialUse`) so they keep running in the background.
- AdMob test ads (app-open on the splash, banner on top) on Android and iOS only.

## Android builds
- `PocketServer-android*.apk` - full build, can share any folder (asks for "All files access").
- `PocketServer-android-play.aab/.apk` - Google Play build: no restricted storage permission, shares the app folder only (Android/data/<id>/files/PocketServer, reachable over USB).

## Build
GitHub Actions (`.github/workflows/build.yml`) generates platform folders with `flutter create`, patches them with `tool/patch_platforms.py`, builds all targets and publishes a GitHub Release.
`tool/gen_web_ui.py` regenerates `lib/host/web_ui.dart` from the original Python `files.py`.

AdMob ids in `lib/ads.dart`, the Android manifest and iOS Info.plist (via `tool/patch_platforms.py`) are Google **test** ids: replace them before release.
