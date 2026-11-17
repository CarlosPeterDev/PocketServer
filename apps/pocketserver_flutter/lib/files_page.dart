import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'file_library.dart';

class FilesPage extends StatefulWidget {
  const FilesPage({super.key});

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  late final Future<FileLibrary> _library = getApplicationDocumentsDirectory()
      .then(
        (directory) => FileLibrary(
          Directory(
            '${directory.path}${Platform.pathSeparator}PocketServer Files',
          ),
        ),
      );
  late Future<List<File>> _files = _readFiles();
  bool _importing = false;

  Future<List<File>> _readFiles() async => (await _library).list();

  Future<void> _importFiles() async {
    setState(() => _importing = true);
    try {
      final selected = await openFiles();
      if (selected.isEmpty) return;
      final library = await _library;
      var imported = 0;
      for (final file in selected) {
        try {
          await library.importFile(file);
          imported++;
        } on Exception {
          // Keep previously imported files if one source is unavailable.
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported $imported of ${selected.length} files.'),
        ),
      );
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to access the file picker or library.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _files = _readFiles();
          _importing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Files')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _importFiles,
        icon: const Icon(Icons.add),
        label: const Text('Import files'),
      ),
      body: FutureBuilder<List<File>>(
        future: _files,
        builder: (context, snapshot) {
          if (_importing || snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
              child: Text('Unable to read the files library.'),
            );
          }
          final files = snapshot.requireData;
          if (files.isEmpty) {
            return const Center(
              child: Text('Import files to add them to your library.'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: files.length,
            itemBuilder: (context, index) => ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(FileLibrary.nameOf(files[index])),
            ),
          );
        },
      ),
    );
  }
}
