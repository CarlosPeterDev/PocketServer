import 'dart:io';

import 'package:file_selector/file_selector.dart';

class FileLibrary {
  FileLibrary(this.root);

  final Directory root;

  Future<List<File>> list() async {
    await root.create(recursive: true);
    final files = <File>[];
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory ||
          !entry.path.split(Platform.pathSeparator).last.startsWith('file-')) {
        continue;
      }
      await for (final file in entry.list(followLinks: false)) {
        if (file is File) files.add(file);
      }
    }
    files.sort(
      (a, b) => nameOf(a).toLowerCase().compareTo(nameOf(b).toLowerCase()),
    );
    return files;
  }

  Future<void> importFile(XFile source) =>
      importStream(source.name, source.openRead());

  Future<void> importStream(String filename, Stream<List<int>> bytes) async {
    await root.create(recursive: true);
    final pending = await root.createTemp('pending-');
    try {
      final name = _safeName(filename);
      final file = File('${pending.path}${Platform.pathSeparator}$name');
      final output = file.openWrite();
      try {
        await output.addStream(bytes);
      } finally {
        await output.close();
      }
      final id = pending.path
          .split(Platform.pathSeparator)
          .last
          .substring('pending-'.length);
      await pending.rename('${root.path}${Platform.pathSeparator}file-$id');
    } finally {
      if (await pending.exists()) await pending.delete(recursive: true);
    }
  }

  static String nameOf(File file) =>
      file.path.split(Platform.pathSeparator).last;

  static String _safeName(String original) {
    var name = original
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .trim();
    name = name.replaceFirst(RegExp(r'[. ]+$'), '');
    if (name.isEmpty) return 'Untitled';
    if (RegExp(
      r'^(con|prn|aux|nul|com[1-9¹²³]|lpt[1-9¹²³]) *(\.|$)',
      caseSensitive: false,
    ).hasMatch(name)) {
      return '_$name';
    }
    return name;
  }
}
