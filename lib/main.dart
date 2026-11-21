import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'config.dart';
import 'host/host_controller.dart';
import 'paths.dart';
import 'ui/home.dart';

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
  runApp(InfinityShareApp(paths: paths, host: host));
}

class InfinityShareApp extends StatelessWidget {
  const InfinityShareApp({super.key, required this.paths, required this.host});
  final AppPaths paths;
  final HostController host;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF6C5CE7);
    return MaterialApp(
      title: 'InfinityShare',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: HomePage(paths: paths, host: host),
    );
  }
}

/// Shared helper: load config from disk.
Future<AppConfig> loadConfig(AppPaths p) => AppConfig.load(p.configFile);
