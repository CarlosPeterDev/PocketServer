import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';
import '../paths.dart';

/// Manage the folders ("spaces") that web hubs and FTP servers can share.
class FoldersPage extends StatefulWidget {
  const FoldersPage({super.key, required this.cfg, required this.paths});
  final AppConfig cfg;
  final AppPaths paths;
  @override
  State<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends State<FoldersPage> {
  AppConfig get cfg => widget.cfg;

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _persist() async {
    await cfg.save(widget.paths.configFile);
    if (mounted) setState(() {});
  }

  Future<void> _add() async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose a folder to use');
    if (dir == null) return;
    if (Platform.isAndroid && !dir.startsWith(widget.paths.defaultStorage.parent.path)) {
      // outside the app's own storage: needs "all files access" (only in the full APK build)
      var ok = await Permission.manageExternalStorage.isGranted;
      if (!ok) ok = (await Permission.manageExternalStorage.request()).isGranted;
      if (!ok) {
        _toast('This folder needs "All files access". The Google Play build can only share the app folder; '
            'use the full APK for any folder.');
        return;
      }
    }
    try {
      Directory(dir).listSync();
    } catch (_) {
      return _toast('Cannot read that folder (permission denied).');
    }
    if (cfg.folders.any((f) => f.path == dir)) return _toast('Already added');
    final nameC = TextEditingController(text: dir.split(RegExp(r'[\\/]')).where((e) => e.isNotEmpty).last);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Space name'),
        content: TextField(controller: nameC, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, nameC.text.trim()), child: const Text('Use this folder')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    cfg.folders.add(SharedFolder(id: FtpServerConfig.newId(), name: name, path: dir));
    await _persist();
  }

  Future<void> _remove(SharedFolder f) async {
    final used = cfg.webHubs.any((w) => w.folderId == f.id) || cfg.ftp.any((s) => s.folderIds.contains(f.id));
    if (used) return _toast('A server is using this folder. Change that server first.');
    cfg.folders.removeWhere((e) => e.id == f.id);
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Folders (spaces)')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('Use a folder'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder_special_outlined),
              title: const Text('App folder'),
              subtitle: Text(widget.paths.defaultStorage.path),
            ),
          ),
          for (final f in cfg.folders)
            Card(
              child: ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(f.name),
                subtitle: Text(f.path),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _remove(f)),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'Each web hub or FTP server picks one of these folders. An FTP server can also pick several: '
            'they are merged as top-level directories.',
          ),
          if (Platform.isAndroid)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Android: the app folder needs no permission. Other folders need "All files access", which only '
                'the full APK asks for (Google Play does not allow it for this kind of app).',
                style: TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
