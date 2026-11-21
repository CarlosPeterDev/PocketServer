# InfinityShare

A personal file hub for Android, iOS, macOS, Linux and Windows.

- **Web hub** on port 2011 (editable): browse, upload, share links, users & permissions, clipboards, notes, stars, activity, text editor.
- **FTP / FTPS servers**: create as many as you like, each with its own name, username, password, port, read-only / anonymous options. Plain FTP, explicit FTPS (AUTH TLS) and implicit FTPS (self-signed certificate).
- **Android** runs the servers in a foreground service, so they keep working in the background.
- iOS suspends apps in the background; desktop servers run while the window is open.

Build: GitHub Actions (`.github/workflows/build.yml`) generates the platform folders with `flutter create`, patches them with `tool/patch_platforms.py`, and publishes APK, AAB, Windows zip, macOS zip/dmg, Linux tar.gz/deb and an unsigned iOS IPA as a GitHub Release.

`tool/gen_web_ui.py` regenerates `lib/host/web_ui.dart` from the original Python `files.py` web page.
