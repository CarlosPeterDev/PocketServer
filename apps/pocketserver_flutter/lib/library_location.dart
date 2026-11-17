import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'file_library.dart';

Future<FileLibrary> openLibrary() async {
  final directory = await getApplicationDocumentsDirectory();
  return FileLibrary(
    Directory('${directory.path}${Platform.pathSeparator}PocketServer Files'),
  );
}
