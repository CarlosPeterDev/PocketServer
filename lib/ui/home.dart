import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ads.dart';
import '../config.dart';
import '../host/host_controller.dart';
import '../paths.dart';
import 'folders_page.dart';
import 'ftp_dialog.dart';
import 'hub_dialog.dart';

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

  Set<int> _ports({String? exceptWeb, String? exceptFtp}) => {
        ...cfg.webHubs.where((w) => w.id != exceptWeb).map((w) => w.port),
        ...cfg.ftp.where((f) => f.id != exceptFtp).map((f) => f.port),
      };

  // ── web hubs ──
  Future<void> _editHub([WebHubConfig? existing]) async {
    final res = await showDialog<WebHubConfig>(
      context: context,
      builder: (_) => HubDialog(initial: existing, cfg: cfg, usedPorts: _ports(exceptWeb: existing?.id)),
    );
    if (res == null) return;
    final i = cfg.webHubs.indexWhere((w) => w.id == res.id);
    if (i >= 0) {
      cfg.webHubs[i] = res;
    } else {
      cfg.webHubs.add(res);
    }
    await _save();
    if (res.enabled) {
      await widget.host.startWeb(res.id);
    } else {
      await widget.host.stopWeb(res.id);
    }
  }

  Future<void> _toggleHub(WebHubConfig w, bool on) async {
    w.enabled = on;
    await cfg.save(widget.paths.configFile);
    if (on) {
      await widget.host.startWeb(w.id);
    } else {
      await widget.host.stopWeb(w.id);
    }
    setState(() {});
  }

  Future<void> _deleteHub(WebHubConfig w) async {
    if (!await _confirm('Delete "${w.name}"?')) return;
    cfg.webHubs.removeWhere((e) => e.id == w.id);
    await _save();
  }

  // ── ftp ──
  Future<void> _editFtp([FtpServerConfig? existing]) async {
    final res = await showDialog<FtpServerConfig>(
      context: context,
      builder: (_) => FtpDialog(initial: existing, cfg: cfg, usedPorts: _ports(exceptFtp: existing?.id)),
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

  Future<bool> _confirm(String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: const Text('The server is stopped and removed. Your files are not touched.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteFtp(FtpServerConfig f) async {
    if (!await _confirm('Delete "${f.name}"?')) return;
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

  Future<void> _folders() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FoldersPage(cfg: cfg, paths: widget.paths)));
    await widget.host.reload();
    if (mounted) setState(() {});
  }

  Future<void> _batteryHelp() async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Keep servers alive'),
        content: const Text(
          'PocketServer runs as a foreground service with a notification, which is the Google-approved way to '
          'stay active. Some phones (Xiaomi, Huawei, Samsung, Oppo...) still stop apps to save battery. '
          'Open the battery settings and set PocketServer to "Unrestricted" / "Not optimized", and also lock it in '
          'the recent-apps list if your phone has that option.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(c);
              try {
                await const AndroidIntent(action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS').launch();
              } catch (_) {
                _toast('Open Settings > Apps > PocketServer > Battery');
              }
            },
            child: const Text('Open battery settings'),
          ),
        ],
      ),
    );
  }

  void _qr(String url) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(color: Colors.white, padding: const EdgeInsets.all(10), child: QrImageView(data: url, size: 220)),
          const SizedBox(height: 10),
          SelectableText(url),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))],
      ),
    );
  }

  void _copy(String text, String msg) {
    Clipboard.setData(ClipboardData(text: text));
    _toast(msg);
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final scheme = Theme.of(context).colorScheme;
    final anyRunning = st.anyRunning;
    return Scaffold(
      appBar: AppBar(
        title: const Text('PocketServer'),
        actions: [
          IconButton(
            tooltip: anyRunning ? 'Stop everything' : 'Start everything',
            icon: Icon(anyRunning ? Icons.stop_circle_outlined : Icons.play_circle_outline),
            onPressed: () => anyRunning ? widget.host.stopAll() : widget.host.startAll(),
          ),
          IconButton(tooltip: 'Folders', icon: const Icon(Icons.folder_open), onPressed: _folders),
          if (Platform.isAndroid)
            IconButton(tooltip: 'Keep alive', icon: const Icon(Icons.battery_saver_outlined), onPressed: _batteryHelp),
        ],
      ),
      floatingActionButton: PopupMenuButton<String>(
        onSelected: (v) => v == 'web' ? _editHub() : _editFtp(),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'web', child: Text('New web hub')),
          PopupMenuItem(value: 'ftp', child: Text('New FTP / FTPS server')),
        ],
        child: FloatingActionButton.extended(
          onPressed: null,
          icon: const Icon(Icons.add),
          label: const Text('Add server'),
        ),
      ),
      body: Column(children: [
        const TopBanner(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Text('Web hubs', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final w in cfg.webHubs) _hubCard(w, scheme),
              const SizedBox(height: 16),
              Text('FTP / FTPS servers', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (cfg.ftp.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('No FTP servers yet. Use "Add server" to create one with your own name, '
                        'username, password, port and folders.',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
                ),
              for (final f in cfg.ftp) _ftpCard(f, scheme),
              const SizedBox(height: 16),
              if (Platform.isIOS)
                Text('iOS pauses apps shortly after you leave them, so servers only work while PocketServer is open.',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                Text('Servers run while this window is open. Closing the window stops them.',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _hubCard(WebHubConfig w, ColorScheme scheme) {
    final s = st.web[w.id];
    final running = s?.running ?? false;
    final url = 'http://$_ip:${w.port}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.language),
            const SizedBox(width: 8),
            Expanded(child: Text(w.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            Switch(value: running, onChanged: (v) => _toggleHub(w, v)),
          ]),
          Text('Port ${w.port} • folder: ${cfg.nameOf(w.folderId)}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          if (s?.error != null) Text(s!.error!, style: TextStyle(color: scheme.error)),
          if (running) ...[
            const SizedBox(height: 4),
            SelectableText(url, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            Text('TV mode: $url/tv', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          ],
          Wrap(alignment: WrapAlignment.end, children: [
            if (running) ...[
              TextButton.icon(onPressed: () => _qr(url), icon: const Icon(Icons.qr_code, size: 16), label: const Text('QR')),
              TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse('http://localhost:${w.port}'), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_browser, size: 16),
                  label: const Text('Open')),
              TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse('http://localhost:${w.port}/tv'), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.tv, size: 16),
                  label: const Text('TV mode')),
            ],
            TextButton.icon(onPressed: () => _copy(url, 'Link copied'), icon: const Icon(Icons.copy, size: 16), label: const Text('Copy')),
            TextButton.icon(onPressed: () => _editHub(w), icon: const Icon(Icons.edit, size: 16), label: const Text('Edit')),
            if (cfg.webHubs.length > 1)
              TextButton.icon(onPressed: () => _deleteHub(w), icon: const Icon(Icons.delete_outline, size: 16), label: const Text('Delete')),
          ]),
        ]),
      ),
    );
  }

  Widget _ftpCard(FtpServerConfig f, ColorScheme scheme) {
    final s = st.ftp[f.id];
    final running = s?.running ?? false;
    final url = '${f.mode.scheme}://$_ip:${f.port}';
    final folders = (f.folderIds.isEmpty ? [kDefaultFolderId] : f.folderIds).map(cfg.nameOf).join(' + ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(f.mode == FtpMode.ftp ? Icons.dns_outlined : Icons.lock_outline),
            const SizedBox(width: 8),
            Expanded(child: Text(f.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            Switch(value: running, onChanged: (v) => _toggleFtp(f, v)),
          ]),
          Text(
              '${f.mode.label} • port ${f.port} • user ${f.anonymous ? 'anonymous / ${f.username}' : f.username}'
              '${f.readOnly ? ' • read-only' : ''}\nFolder: $folders',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          if (s?.error != null) Text(s!.error!, style: TextStyle(color: scheme.error)),
          if (running) ...[
            const SizedBox(height: 4),
            SelectableText(url),
            Text('${s!.connections} connection${s.connections == 1 ? '' : 's'}',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            if (f.mode != FtpMode.ftp)
              Text('Self-signed certificate: accept it in your FTP client.',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          ],
          Wrap(alignment: WrapAlignment.end, children: [
            TextButton.icon(onPressed: () => _copy(url, 'Address copied'), icon: const Icon(Icons.copy, size: 16), label: const Text('Copy')),
            TextButton.icon(onPressed: () => _editFtp(f), icon: const Icon(Icons.edit, size: 16), label: const Text('Edit')),
            TextButton.icon(onPressed: () => _deleteFtp(f), icon: const Icon(Icons.delete_outline, size: 16), label: const Text('Delete')),
          ]),
        ]),
      ),
    );
  }
}
