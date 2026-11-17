# Verification

| Check | Where it runs | Coverage |
| --- | --- | --- |
| Shared unit tests and Dart analysis | Android and Windows CI jobs | OS mapping and reading host diagnostics |
| Flutter analysis and tests | Android and Windows CI jobs | Dashboard rendering and Dart method-channel behavior with a mock |
| Native build and packaging | Android and Windows CI jobs | Kotlin and C++ compilation, Android APK/AAB, Windows x64 portable and installer distributions |
| Secret scan | Linux CI job | Git history with redacted Gitleaks output |

The Flutter tests use a mocked native channel. Run the following checks on
hardware to exercise the platform implementations.

1. Open the push workflow and download the artifact for the target platform.
   Verify the included SHA-256 values against the extracted packages.
2. On Android 8 or newer, install the APK. On Windows 10 or 11 x64, install
   the setup executable or extract the portable ZIP before starting the app.
3. Open PocketServer. Confirm that the platform name and processor count match
   the host, and that Available app storage displays a number.
4. Select Refresh storage. Confirm that the app displays a new reading without
   restarting. The reading measures space available to the current app or user
   on its app-data volume and may differ from total free space elsewhere.
5. On Windows, verify removal from Settings if you used the installer. On
   Android, uninstall the test APK using system settings.

The push APK and AAB use CI test signing. The versioned release workflow
requires Android release signing credentials and only runs when dispatched on
a matching version tag.

## Local website

1. Open **Local website** and select a nonempty UTF-8 HTML file up to 1 MiB.
2. Copy the displayed address to a browser on the same device. The
   selected document should appear.
3. Return to PocketServer and select **Stop hosting**. A browser reload should
   report that it cannot connect.
4. Repeat with a second HTML file and cancel the picker while the first is
   running. The first website should remain available.

CI exercises the Android socket server on the JVM and the Windows socket
server on the Windows runner. The preview serves one HTML file on IPv4
loopback while the app is running. Site directories, HTTPS and persistent
services are separate features.
