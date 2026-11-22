import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:permission_handler/permission_handler.dart';

import 'config.dart';
import 'host/host_controller.dart';
import 'l10n.dart';
import 'paths.dart';
import 'settings.dart';
import 'ui/onboarding.dart';
import 'ui/splash.dart';

/// Starts the server host (and on Android the background service). Only called after the privacy policy is accepted.
Future<HostController> bootHost(AppPaths paths) async {
  if (Platform.isAndroid) {
    try {
      await Permission.notification.request();
    } catch (_) {}
    await AndroidServiceHost.configureService();
  }
  return HostController.create(paths);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final paths = await AppPaths.resolve();
  final settings = await AppSettings.load(paths.settingsFile);
  // first launch: follow the phone (Arabic phone -> Arabic, anything else -> English); afterwards the saved choice
  Lang.set(settings.lang ?? Lang.deviceDefault());
  final host = settings.privacyAccepted ? await bootHost(paths) : null;
  runApp(PocketServerApp(paths: paths, settings: settings, host: host));
}

class PocketServerApp extends StatelessWidget {
  const PocketServerApp({super.key, required this.paths, required this.settings, required this.host});
  final AppPaths paths;
  final AppSettings settings;
  final HostController? host;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF6C5CE7);
    return ValueListenableBuilder<Locale>(
      valueListenable: Lang.locale,
      builder: (context, locale, _) => MaterialApp(
        title: 'PocketServer',
        debugShowCheckedModeBanner: false,
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
        home: host != null
            ? SplashPage(paths: paths, host: host!)
            : OnboardingPage(paths: paths, settings: settings, boot: () => bootHost(paths)),
      ),
    );
  }
}

/// Shared helper: load config from disk.
Future<AppConfig> loadConfig(AppPaths p) => AppConfig.load(p.configFile);
