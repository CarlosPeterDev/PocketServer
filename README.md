# PocketServer

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
