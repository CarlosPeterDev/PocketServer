import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketserver_flutter/file_library.dart';

void main() {
  test('preserves the content of two imports with the same name', () async {
    final root = await Directory.systemTemp.createTemp('pocketserver-files-');
    addTearDown(() => root.delete(recursive: true));
    final library = FileLibrary(root);
    await library.importFile(
      XFile.fromData(Uint8List.fromList([1]), name: 'report.txt'),
    );
    await library.importFile(
      XFile.fromData(Uint8List.fromList([2]), name: 'report.txt'),
    );

    final files = await FileLibrary(root).list();
    expect(files.map(FileLibrary.nameOf), ['report.txt', 'report.txt']);
    expect(
      await Future.wait(files.map((file) => file.readAsBytes())),
      unorderedEquals([
        [1],
        [2],
      ]),
    );
  });
}
