import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'config.dart';
import 'host/host_controller.dart';
import 'paths.dart';
import 'ui/splash.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final paths = await AppPaths.resolve();
  if (Platform.isAndroid) {
    try {
      await Permission.notification.request();
    } catch (_) {}
    await AndroidServiceHost.configureService();
  }
  final host = await HostController.create(paths);
  runApp(PocketServerApp(paths: paths, host: host));
}

class PocketServerApp extends StatelessWidget {
  const PocketServerApp({super.key, required this.paths, required this.host});
  final AppPaths paths;
  final HostController host;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF6C5CE7);
    return MaterialApp(
      title: 'PocketServer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: SplashPage(paths: paths, host: host),
    );
  }
}

/// Shared helper: load config from disk.
Future<AppConfig> loadConfig(AppPaths p) => AppConfig.load(p.configFile);
