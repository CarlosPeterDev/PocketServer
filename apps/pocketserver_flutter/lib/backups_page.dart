import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'backup_library.dart';
import 'library_location.dart';

class BackupsPage extends StatefulWidget {
  const BackupsPage({super.key});

  @override
  State<BackupsPage> createState() => _BackupsPageState();
}

class _BackupsPageState extends State<BackupsPage> {
  late final _library = openLibrary().then(BackupLibrary.new);
  late Future<List<Directory>> _snapshots = _load();
  bool _busy = false;

  Future<List<Directory>> _load() async => (await _library).list();

  Future<void> _run({Directory? snapshot}) async {
    setState(() => _busy = true);
    String message;
    var restored = 0;
    try {
      final library = await _library;
      if (snapshot == null) {
        await library.create();
        message = 'Local backup created.';
      } else {
        await for (final count in library.restore(snapshot)) {
          restored = count;
        }
        message = 'Restored $restored files as new copies.';
      }
    } on StateError catch (error) {
      message = error.message;
    } on Exception {
      message = snapshot == null
          ? 'Could not create the backup.'
          : 'Restore stopped after $restored files.';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _snapshots = _load();
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backups')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _run(),
        icon: const Icon(Icons.backup_outlined),
        label: const Text('Create backup'),
      ),
      body: FutureBuilder<List<Directory>>(
        future: _snapshots,
        builder: (context, snapshot) {
          if (_busy || snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to read local backups.'));
          }
          final backups = snapshot.requireData;
          if (backups.isEmpty) {
            return const Center(child: Text('No local backups yet.'));
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              const ListTile(
                title: Text(
                  'Backups are stored on this device. Restores add new copies.',
                ),
              ),
              for (final backup in backups)
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: Text(
                    BackupLibrary.createdAt(backup)?.toString() ??
                        BackupLibrary.label(backup),
                  ),
                  trailing: TextButton(
                    onPressed: () => _run(snapshot: backup),
                    child: const Text('Restore'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
