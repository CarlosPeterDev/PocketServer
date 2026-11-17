import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart';

import 'dashboard_server.dart';
import 'library_location.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  DashboardServer? _server;
  bool _busy = false;
  String? _error;

  Future<InternetAddress?> _selectAddress() async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    final addresses = <String, InternetAddress>{
      for (final item in interfaces)
        for (final address in item.addresses)
          if (DashboardServer.isPrivateIPv4(address)) address.address: address,
    };
    if (!mounted) return null;
    if (addresses.isEmpty) throw StateError('No private IPv4 address is available.');
    return showDialog<InternetAddress>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select LAN address'),
        children: [
          for (final address in addresses.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, address),
              child: Text(address.address),
            ),
        ],
      ),
    );
  }

  Future<Uint8List?> _readPem() async {
    final file = await openFile();
    if (file == null) return null;
    if (await file.length() > 128 * 1024) throw StateError('PEM file is too large.');
    return file.readAsBytes();
  }

  Future<void> _start({required bool lan}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      SecurityContext? tls;
      InternetAddress? address;
      if (lan) {
        address = await _selectAddress();
        if (address == null || !mounted) return;
        _showMessage('Select the PEM certificate chain.');
        final certificate = await _readPem();
        if (certificate == null || !mounted) return;
        _showMessage('Select the matching PEM private key.');
        final key = await _readPem();
        if (key == null || !mounted) return;
        tls = SecurityContext()
          ..useCertificateChainBytes(certificate)
          ..usePrivateKeyBytes(key);
      }
      final server = await DashboardServer.start(await openLibrary(), address: address, tls: tls);
      if (!mounted) {
        await server.close();
        return;
      }
      setState(() => _server = server);
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) setState(() => _error = 'Could not start the dashboard. Check the selected files and network.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String text) {
    final messages = ScaffoldMessenger.of(context);
    messages
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _stop() async {
    final server = _server;
    setState(() => _server = null);
    await server?.close();
  }

  @override
  void dispose() {
    _server?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final server = _server;
    return Scaffold(
      appBar: AppBar(title: const Text('Web dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (server == null) ...[
            const Text('Browse, upload and download PocketServer files. Keep this screen open while serving.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : () => _start(lan: false),
              child: const Text('Start on this device'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _start(lan: true),
              child: const Text('Start LAN HTTPS'),
            ),
            const Text('LAN mode requires a PEM certificate and matching key. Use a certificate your devices trust for the selected IP address.'),
          ] else ...[
            ListTile(
              title: const Text('Dashboard address'),
              subtitle: SelectableText(server.url.toString()),
              trailing: IconButton(
                tooltip: 'Copy address',
                icon: const Icon(Icons.copy),
                onPressed: () => Clipboard.setData(ClipboardData(text: server.url.toString())),
              ),
            ),
            const ListTile(title: Text('Username'), subtitle: Text('pocketserver')),
            ListTile(title: const Text('Session password'), subtitle: SelectableText(server.password)),
            OutlinedButton(onPressed: _stop, child: const Text('Stop server')),
          ],
          if (_busy) const LinearProgressIndicator(),
          if (_error case final error?) Text(error),
        ],
      ),
    );
  }
}
