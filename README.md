# PocketServer

PocketServer is a CasaOS-inspired home server for personal storage and locally owned media. The current app provides host and storage diagnostics.

Flutter application targeting Android 8.0+ and Windows 10/11. The initial
application displays host diagnostics and available app storage on the native
targets. The shared Dart contracts
live in `packages/contracts`.

Use Flutter 3.50.0 and follow Flutter's Android or Windows toolchain setup.

```sh
cd apps/pocketserver_flutter
flutter pub get
flutter analyze
flutter test
flutter run
```

GitHub Actions builds an Android APK and AAB and a Windows x64 portable archive
and installer. Android CI packages use a debug signing key and are for testing.

## Versioned releases

Update the app version and add a matching `## vMAJOR.MINOR.PATCH` section in
`CHANGELOG.md`. Push the corresponding version tag, then dispatch
`release.yml` using that tag. The workflow tests both platforms, checks
artifact hashes, and requires the Android signing secrets
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`
and `ANDROID_KEY_PASSWORD`. Keep the keystore and passwords outside Git.
Windows packages currently use an unsigned installer.

See [verification.md](docs/verification.md) for test coverage and target-device
smoke checks.
