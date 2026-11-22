import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';


class AppPaths {
  AppPaths(this.dataDir, this.defaultStorage);
  final Directory dataDir; // config, certs (private)
  final Directory defaultStorage; // shared files root

  File get configFile => File(p.join(dataDir.path, 'config.json'));
  File get settingsFile => File(p.join(dataDir.path, 'settings.json'));
  Directory get certDir => Directory(p.join(dataDir.path, 'tls'));


  static Future<AppPaths> resolve() async {
    final support = await getApplicationSupportDirectory();
    Directory docs = await getApplicationDocumentsDirectory();
    if (Platform.isAndroid) {
      // app-specific external storage: needs no permission, visible over USB / file managers
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) docs = ext;
      } catch (_) {}
    }
    final data = Directory(p.join(support.path, 'pocketserver'));
    final storage = Directory(p.join(docs.path, 'PocketServer'));
    await data.create(recursive: true);
    await storage.create(recursive: true);
    return AppPaths(data, storage);
  }
}
