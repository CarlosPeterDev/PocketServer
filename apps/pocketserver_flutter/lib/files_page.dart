import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_filex/open_filex.dart';

import 'file_library.dart';
import 'library_location.dart';

enum LibraryView {
  files('Files', Icons.folder_outlined, {}),
  movies('Movies', Icons.movie_outlined, {
    'mp4',
    'mkv',
    'webm',
    'mov',
    'avi',
    'm4v',
  }),
  photos('Photos', Icons.photo_library_outlined, {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'bmp',
    'heic',
  }),
  music('Music', Icons.music_note_outlined, {
    'mp3',
    'm4a',
    'flac',
    'wav',
    'ogg',
    'aac',
    'opus',
  });

  const LibraryView(this.title, this.icon, this.extensions);
  final String title;
  final IconData icon;
  final Set<String> extensions;

  bool includes(String name) {
    if (this == files) return true;
    final dot = name.lastIndexOf('.');
    return dot > 0 &&
        extensions.contains(name.substring(dot + 1).toLowerCase());
  }
}

class FilesPage extends StatefulWidget {
  const FilesPage({super.key, this.view = LibraryView.files});

  final LibraryView view;

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  late final Future<FileLibrary> _library = openLibrary();
  late Future<List<File>> _files = _readFiles();
  bool _importing = false;
  String _query = '';

  Future<List<File>> _readFiles() async => (await _library).list();

  Future<void> _open(File file) async {
    String? error;
    try {
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) error = result.message;
    } on Exception {
      error = 'Unable to open this file.';
    }
    if (mounted && error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

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
      appBar: AppBar(title: Text(widget.view.title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _importFiles,
        icon: const Icon(Icons.add),
        label: const Text('Import files'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search library',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<File>>(
              future: _files,
              builder: (context, snapshot) {
                if (_importing ||
                    snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Unable to read the files library.'),
                  );
                }
                final files = snapshot.requireData.where((file) {
                  final name = FileLibrary.nameOf(file);
                  return widget.view.includes(name) &&
                      name.toLowerCase().contains(_query);
                }).toList();
                if (files.isEmpty) {
                  return Center(
                    child: Text(
                      _query.isEmpty
                          ? 'No ${widget.view.title.toLowerCase()} in your library.'
                          : 'No matching files.',
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return ListTile(
                      leading: widget.view == LibraryView.photos
                          ? Image.file(
                              file,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              cacheWidth: 96,
                              errorBuilder: (_, _, _) => Icon(widget.view.icon),
                            )
                          : Icon(widget.view.icon),
                      title: Text(FileLibrary.nameOf(file)),
                      onTap: () => _open(file),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
