import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'config.dart';

class AppPaths {
  AppPaths(this.dataDir, this.defaultStorage);
  final Directory dataDir; // config, certs (private)
  final Directory defaultStorage; // shared files root

  File get configFile => File(p.join(dataDir.path, 'config.json'));
  Directory get certDir => Directory(p.join(dataDir.path, 'tls'));

  String storageFor(AppConfig c) => c.storageDir.trim().isEmpty ? defaultStorage.path : c.storageDir.trim();

  static Future<AppPaths> resolve() async {
    final support = await getApplicationSupportDirectory();
    final docs = await getApplicationDocumentsDirectory();
    final data = Directory(p.join(support.path, 'infinityshare'));
    final storage = Directory(p.join(docs.path, 'InfinityShare'));
    await data.create(recursive: true);
    await storage.create(recursive: true);
    return AppPaths(data, storage);
  }
}
