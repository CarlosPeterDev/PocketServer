import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../host/host_controller.dart';
import '../paths.dart';
import 'ftp_dialog.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.paths, required this.host});
  final AppPaths paths;
  final HostController host;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppConfig cfg = AppConfig();
  HostStatus st = HostStatus();
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    st = widget.host.current;
    widget.host.status.listen((s) {
      if (mounted) setState(() => st = s);
    });
    _load();
  }

  Future<void> _load() async {
    cfg = await AppConfig.load(widget.paths.configFile);
    if (mounted) setState(() => loaded = true);
  }

  Future<void> _save() async {
    await cfg.save(widget.paths.configFile);
    await widget.host.reload();
    if (mounted) setState(() {});
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));

  String get _ip => st.ips.isEmpty ? 'localhost' : st.ips.first;
  String get _webUrl => 'http://$_ip:${cfg.webPort}';

  Future<void> _editFtp([FtpServerConfig? existing]) async {
    final used = <int>{cfg.webPort, ...cfg.ftp.where((f) => f.id != existing?.id).map((f) => f.port)};
    final res = await showDialog<FtpServerConfig>(
      context: context,
      builder: (_) => FtpDialog(initial: existing, usedPorts: used),
    );
    if (res == null) return;
    final i = cfg.ftp.indexWhere((f) => f.id == res.id);
    if (i >= 0) {
      cfg.ftp[i] = res;
    } else {
      cfg.ftp.add(res);
    }
    await _save();
    if (res.enabled) {
      await widget.host.startFtp(res.id);
    } else {
      await widget.host.stopFtp(res.id);
    }
  }

  Future<void> _deleteFtp(FtpServerConfig f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete "${f.name}"?'),
        content: const Text('The server is stopped and removed. Your files are not touched.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    cfg.ftp.removeWhere((e) => e.id == f.id);
    await _save();
  }

  Future<void> _toggleFtp(FtpServerConfig f, bool on) async {
    f.enabled = on;
    await cfg.save(widget.paths.configFile);
    if (on) {
      await widget.host.startFtp(f.id);
    } else {
      await widget.host.stopFtp(f.id);
    }
    setState(() {});
  }

  Future<void> _toggleWeb(bool on) async {
    cfg.webEnabled = on;
    await cfg.save(widget.paths.configFile);
    if (on) {
      await widget.host.startWeb();
    } else {
      await widget.host.stopWeb();
    }
    setState(() {});
  }

  Future<void> _settings() async {
    final portC = TextEditingController(text: '${cfg.webPort}');
    final dirC = TextEditingController(text: cfg.storageDir);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Settings'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: portC,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Web server port'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: dirC,
              decoration: InputDecoration(
                labelText: 'Shared folder (empty = default)',
                helperText: 'Default: ${widget.paths.defaultStorage.path}',
                helperMaxLines: 3,
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final port = int.tryParse(portC.text.trim());
    if (port == null || port < 1 || port > 65535) return _toast('Invalid port');
    final dir = dirC.text.trim();
    if (dir.isNotEmpty) {
      try {
        await Directory(dir).create(recursive: true);
      } catch (_) {
        return _toast('Cannot use that folder');
      }
    }
    cfg.webPort = port;
    cfg.storageDir = dir;
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final scheme = Theme.of(context).colorScheme;
    final anyRunning = st.webRunning || st.ftp.values.any((f) => f.running);
    return Scaffold(
      appBar: AppBar(
        title: const Text('InfinityShare'),
        actions: [
          IconButton(
            tooltip: anyRunning ? 'Stop everything' : 'Start everything',
            icon: Icon(anyRunning ? Icons.stop_circle_outlined : Icons.play_circle_outline),
            onPressed: () async {
              if (anyRunning) {
                await widget.host.stopAll();
              } else {
                await widget.host.startAll();
              }
            },
          ),
          IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings_outlined), onPressed: _settings),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editFtp(),
        icon: const Icon(Icons.add),
        label: const Text('FTP / FTPS server'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          _webCard(scheme),
          const SizedBox(height: 20),
          Text('FTP / FTPS servers', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (cfg.ftp.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No FTP servers yet. Tap the button below to create one with your own name, '
                  'username, password and port.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          for (final f in cfg.ftp) _ftpCard(f, scheme),
          const SizedBox(height: 16),
          Text(
            'Folder: ${cfg.storageDir.isEmpty ? widget.paths.defaultStorage.path : cfg.storageDir}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if (Platform.isIOS)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'iOS pauses apps shortly after you leave them, so servers only work while InfinityShare is open.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Servers run while this window is open. Closing the window stops them.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  Widget _webCard(ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.language),
            const SizedBox(width: 8),
            const Expanded(child: Text('Web file hub', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
            Switch(value: st.webRunning, onChanged: _toggleWeb),
          ]),
          if (st.webError != null)
            Text(st.webError!, style: TextStyle(color: scheme.error))
          else if (st.webRunning) ...[
            const SizedBox(height: 8),
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: QrImageView(data: _webUrl, size: 150),
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(_webUrl, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            for (final ip in st.ips.skip(1))
              Text('http://$ip:${cfg.webPort}', style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy link'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _webUrl));
                  _toast('Link copied');
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_browser, size: 18),
                label: const Text('Open'),
                onPressed: () => launchUrl(Uri.parse('http://localhost:${cfg.webPort}'),
                    mode: LaunchMode.externalApplication),
              ),
            ]),
          ] else
            Text('Stopped. Turn it on to share files over your network.',
                style: TextStyle(color: scheme.onSurfaceVariant)),
        ]),
      ),
    );
  }

  Widget _ftpCard(FtpServerConfig f, ColorScheme scheme) {
    final s = st.ftp[f.id];
    final running = s?.running ?? false;
    final url = '${f.mode.scheme}://$_ip:${f.port}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(f.mode == FtpMode.ftp ? Icons.dns_outlined : Icons.lock_outline),
            const SizedBox(width: 8),
            Expanded(
              child: Text(f.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            Switch(value: running, onChanged: (v) => _toggleFtp(f, v)),
          ]),
          Text('${f.mode.label} • port ${f.port} • user ${f.anonymous ? 'anonymous / ${f.username}' : f.username}'
              '${f.readOnly ? ' • read-only' : ''}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          if (s?.error != null) Text(s!.error!, style: TextStyle(color: scheme.error)),
          if (running) ...[
            const SizedBox(height: 4),
            SelectableText(url),
            Text('${s!.connections} connection${s.connections == 1 ? '' : 's'}',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            if (f.mode != FtpMode.ftp)
              Text('Uses a self-signed certificate: accept it in your FTP client.',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          ],
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: url));
                  _toast('Address copied');
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy')),
            TextButton.icon(
                onPressed: () => _editFtp(f), icon: const Icon(Icons.edit, size: 16), label: const Text('Edit')),
            TextButton.icon(
                onPressed: () => _deleteFtp(f),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete')),
          ]),
        ]),
      ),
    );
  }
}
