import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketserver_flutter/backup_library.dart';
import 'package:pocketserver_flutter/file_library.dart';

void main() {
  late Directory root;
  late FileLibrary library;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pocketserver-files-');
    library = FileLibrary(Directory.fromUri(root.uri.resolve('library/')));
  });

  tearDown(() => root.delete(recursive: true));

  Future<void> importReport(int content) async {
    final source = File.fromUri(root.uri.resolve('report.txt'));
    await source.writeAsBytes([content]);
    await library.importFile(XFile(source.path));
  }

  test('preserves the content of two imports with the same name', () async {
    await importReport(1);
    await importReport(2);
    final files = await FileLibrary(library.root).list();

    expect(files.map(FileLibrary.nameOf), ['report.txt', 'report.txt']);
    expect(
      await Future.wait(files.map((file) => file.readAsBytes())),
      unorderedEquals([
        [1],
        [2],
      ]),
    );
  });

  test(
    'restores a local snapshot without replacing an existing file',
    () async {
      await importReport(1);
      final backups = BackupLibrary(library);
      await backups.create();
      await importReport(2);

      final snapshot = (await BackupLibrary(library).list()).single;
      expect(await backups.restore(snapshot).toList(), [1]);
      final files = await library.list();
      expect(
        await Future.wait(files.map((file) => file.readAsBytes())),
        unorderedEquals([
          [1],
          [1],
          [2],
        ]),
      );
    },
  );
}
