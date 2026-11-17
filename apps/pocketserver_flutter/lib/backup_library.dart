import 'dart:io';

import 'package:file_selector/file_selector.dart';

import 'file_library.dart';

class BackupLibrary {
  BackupLibrary(this.files) : root = Directory('${files.root.path} Backups');

  final FileLibrary files;
  final Directory root;

  Future<List<Directory>> list() async {
    await root.create(recursive: true);
    final snapshots = <Directory>[];
    await for (final item in root.list(followLinks: false)) {
      if (item is Directory && label(item).startsWith('snapshot-')) {
        snapshots.add(item);
      }
    }
    snapshots.sort((a, b) => label(b).compareTo(label(a)));
    return snapshots;
  }

  Future<void> create() async {
    final sources = await files.list();
    if (sources.isEmpty) {
      throw StateError('Import files before creating a backup.');
    }
    await root.create(recursive: true);
    final pending = await root.createTemp('pending-');
    try {
      final snapshot = FileLibrary(pending);
      for (final file in sources) {
        await snapshot.importFile(
          XFile(file.path, name: FileLibrary.nameOf(file)),
        );
      }
      final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
      await pending.rename(
        '${root.path}${Platform.pathSeparator}snapshot-$timestamp',
      );
    } finally {
      if (await pending.exists()) await pending.delete(recursive: true);
    }
  }

  Stream<int> restore(Directory snapshot) async* {
    var restored = 0;
    for (final file in await FileLibrary(snapshot).list()) {
      await files.importFile(XFile(file.path, name: FileLibrary.nameOf(file)));
      yield ++restored;
    }
  }

  static String label(Directory directory) =>
      directory.path.split(Platform.pathSeparator).last;

  static DateTime? createdAt(Directory directory) {
    final timestamp = int.tryParse(
      label(directory).substring('snapshot-'.length),
    );
    return timestamp == null
        ? null
        : DateTime.fromMicrosecondsSinceEpoch(timestamp, isUtc: true).toLocal();
  }
}
