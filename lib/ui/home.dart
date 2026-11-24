import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ads.dart';
import '../battery.dart';
import '../config.dart';
import '../host/host_controller.dart';
import '../l10n.dart';
import '../paths.dart';
import 'dashboard_page.dart';
import 'dav_dialog.dart';
import 'ftp_dialog.dart';
import 'help_page.dart';
import 'hub_dialog.dart';
import 'settings_page.dart';

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
  bool guideHidden = true; // until we know

  @override
  void initState() {
    super.initState();
    st = widget.host.current;
    widget.host.status.listen((s) {
      if (mounted) setState(() => st = s);
    });
    _load();
    guideHidden = File(p.join(widget.paths.dataDir.path, 'guide_dismissed')).existsSync();
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) => Future<void>.delayed(const Duration(milliseconds: 600), _maybeAskBattery));
    }
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

  /// Other addresses of this phone (WiFi vs hotspot ...) plus a hint for "not found" on other devices.
  Widget _altAddresses(ColorScheme scheme, String scheme0, int port, String suffix) {
    final others = st.ips.skip(1).toList();
    final small = TextStyle(color: scheme.onSurfaceVariant, fontSize: 12);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (others.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(tr('If this address does not open on another device, try:'), style: small),
        for (final ip in others)
          SelectableText('$scheme0://$ip:$port$suffix', textDirection: TextDirection.ltr, style: small),
      ],
      const SizedBox(height: 4),
      Text(tr('Not found? Both devices must be on the same WiFi (or one on the other\'s hotspot). Turn off "AP / client isolation" in the router and turn off VPN.'),
          style: small),
    ]);
  }

  Set<int> _ports({String? exceptWeb, String? exceptFtp, String? exceptDav}) => {
        ...cfg.webHubs.where((w) => w.id != exceptWeb).map((w) => w.port),
        ...cfg.ftp.where((f) => f.id != exceptFtp).map((f) => f.port),
        ...cfg.dav.where((d) => d.id != exceptDav).map((d) => d.port),
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
    if (!await _confirm(tr('Delete "{name}"?', {'name': tr(w.name)}))) return;
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

  // ── webdav ──
  Future<void> _editDav([DavConfig? existing]) async {
    final res = await showDialog<DavConfig>(
      context: context,
      builder: (_) => DavDialog(initial: existing, cfg: cfg, usedPorts: _ports(exceptDav: existing?.id)),
    );
    if (res == null) return;
    final i = cfg.dav.indexWhere((d) => d.id == res.id);
    if (i >= 0) {
      cfg.dav[i] = res;
    } else {
      cfg.dav.add(res);
    }
    await _save();
    if (res.enabled) {
      await widget.host.startDav(res.id);
    } else {
      await widget.host.stopDav(res.id);
    }
  }

  Future<void> _toggleDav(DavConfig d, bool on) async {
    d.enabled = on;
    await cfg.save(widget.paths.configFile);
    if (on) {
      await widget.host.startDav(d.id);
    } else {
      await widget.host.stopDav(d.id);
    }
    setState(() {});
  }

  Future<void> _deleteDav(DavConfig d) async {
    if (!await _confirm(tr('Delete "{name}"?', {'name': tr(d.name)}))) return;
    cfg.dav.removeWhere((e) => e.id == d.id);
    await _save();
  }

  Future<bool> _confirm(String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(tr('The server is stopped and removed. Your files are not touched.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Delete'))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteFtp(FtpServerConfig f) async {
    if (!await _confirm(tr('Delete "{name}"?', {'name': tr(f.name)}))) return;
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

  void _help([String? topic]) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => HelpPage(host: widget.host, topic: topic)));

  void _hideGuide() {
    try {
      File(p.join(widget.paths.dataDir.path, 'guide_dismissed')).writeAsStringSync('1');
    } catch (_) {}
    setState(() => guideHidden = true);
  }

  Widget _sectionTitle(String title, String topic) => Row(children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        IconButton(
          tooltip: tr('Guide'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.help_outline, size: 20),
          onPressed: () => _help(topic),
        ),
      ]);

  /// On every launch (until fixed or dismissed for good): explain, then show the small system "Allow" box.
  Future<void> _maybeAskBattery() async {
    if (!Platform.isAndroid || !mounted) return;
    if (await batteryUnrestricted()) return;
    final marker = batteryMarker(widget.paths);
    if (marker.existsSync()) return;
    if (!mounted) return;
    await showBatteryHelp(context, marker: marker);
  }

  void _qr(String url) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(color: Colors.white, padding: const EdgeInsets.all(10), child: QrImageView(data: url, size: 220)),
          const SizedBox(height: 10),
          SelectableText(url, textDirection: TextDirection.ltr),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Close')))],
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
            tooltip: anyRunning ? tr('Stop everything') : tr('Start everything'),
            icon: Icon(anyRunning ? Icons.stop_circle_outlined : Icons.play_circle_outline),
            onPressed: () => anyRunning ? widget.host.stopAll() : widget.host.startAll(),
          ),
          IconButton(
            tooltip: tr('Dashboard'),
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => DashboardPage(cfg: cfg, paths: widget.paths, host: widget.host))),
          ),
          IconButton(
            tooltip: tr('Settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => SettingsPage(paths: widget.paths, host: widget.host))),
          ),
        ],
      ),
      floatingActionButton: PopupMenuButton<String>(
        onSelected: (v) => v == 'web' ? _editHub() : (v == 'dav' ? _editDav() : _editFtp()),
        itemBuilder: (_) => [
          PopupMenuItem(value: 'web', child: Text(tr('New web hub'))),
          PopupMenuItem(value: 'ftp', child: Text(tr('New FTP / FTPS server'))),
          PopupMenuItem(value: 'dav', child: Text(tr('New WebDAV server'))),
        ],
        child: FloatingActionButton.extended(
          onPressed: null,
          icon: const Icon(Icons.add),
          label: Text(tr('Add server')),
        ),
      ),
      body: Column(children: [
        const TopBanner(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              if (!guideHidden)
                Card(
                  color: scheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 4, 8),
                    child: Row(children: [
                      Icon(Icons.menu_book_outlined, color: scheme.onPrimaryContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tr('New here? Read the quick guide (2 minutes).'),
                              style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
                          TextButton(onPressed: () => _help(), child: Text(tr('Open guide'))),
                        ]),
                      ),
                      IconButton(
                          tooltip: tr('Close'), icon: const Icon(Icons.close), onPressed: _hideGuide),
                    ]),
                  ),
                ),
              _sectionTitle(tr('Web hubs'), 'web'),
              const SizedBox(height: 8),
              for (final w in cfg.webHubs) _hubCard(w, scheme),
              const SizedBox(height: 16),
              _sectionTitle(tr('FTP / FTPS servers'), 'ftp'),
              const SizedBox(height: 8),
              if (cfg.ftp.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(tr('No FTP servers yet. Use "Add server" to create one with your own name, username, password, port and folders.'),
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
                ),
              for (final f in cfg.ftp) _ftpCard(f, scheme),
              if (cfg.dav.isNotEmpty) ...[
                const SizedBox(height: 16),
                _sectionTitle(tr('WebDAV drives'), 'webdav'),
                const SizedBox(height: 8),
                for (final d in cfg.dav) _davCard(d, scheme),
              ],
              const SizedBox(height: 16),
              if (Platform.isIOS)
                Text(tr('iOS pauses apps shortly after you leave them, so servers only work while PocketServer is open.'),
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                Text(tr('Servers run while this window is open. Closing the window stops them.'),
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
            Expanded(child: Text(tr(w.name), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            Switch(value: running, onChanged: (v) => _toggleHub(w, v)),
          ]),
          Text(tr('Port {port}', {'port': w.port}),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          if (s?.error != null) Text(s!.error!, style: TextStyle(color: scheme.error)),
          if (running) ...[
            const SizedBox(height: 4),
            SelectableText(url, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            _altAddresses(scheme, 'http', w.port, ''),
          ],
          Wrap(alignment: WrapAlignment.end, children: [
            if (running) ...[
              TextButton.icon(onPressed: () => _qr(url), icon: const Icon(Icons.qr_code, size: 16), label: Text(tr('QR'))),
              TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse('http://localhost:${w.port}'), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_browser, size: 16),
                  label: Text(tr('Open'))),
            ],
            TextButton.icon(onPressed: () => _copy(url, tr('Link copied')), icon: const Icon(Icons.copy, size: 16), label: Text(tr('Copy'))),
            TextButton.icon(onPressed: () => _editHub(w), icon: const Icon(Icons.edit, size: 16), label: Text(tr('Edit'))),
            if (cfg.webHubs.length > 1)
              TextButton.icon(onPressed: () => _deleteHub(w), icon: const Icon(Icons.delete_outline, size: 16), label: Text(tr('Delete'))),
          ]),
        ]),
      ),
    );
  }

  Widget _davCard(DavConfig d, ColorScheme scheme) {
    final s = st.dav[d.id];
    final running = s?.running ?? false;
    final url = 'http://$_ip:${d.port}/';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.storage_outlined),
            const SizedBox(width: 8),
            Expanded(child: Text(tr(d.name), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            Switch(value: running, onChanged: (v) => _toggleDav(d, v)),
          ]),
          Text('${tr('Port {port} • user {user}', {'port': d.port, 'user': d.username})}${d.readOnly ? ' • ${tr('read-only')}' : ''}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          if (s?.error != null) Text(s!.error!, style: TextStyle(color: scheme.error)),
          if (running) ...[
            const SizedBox(height: 4),
            SelectableText(url, textDirection: TextDirection.ltr),
            _altAddresses(scheme, 'http', d.port, '/'),
            Text(tr('Windows: Map network drive. macOS: Connect to Server. Linux/Android: any WebDAV client.'),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          ],
          Wrap(alignment: WrapAlignment.end, children: [
            TextButton.icon(onPressed: () => _copy(url, tr('Address copied')), icon: const Icon(Icons.copy, size: 16), label: Text(tr('Copy'))),
            TextButton.icon(onPressed: () => _editDav(d), icon: const Icon(Icons.edit, size: 16), label: Text(tr('Edit'))),
            TextButton.icon(onPressed: () => _deleteDav(d), icon: const Icon(Icons.delete_outline, size: 16), label: Text(tr('Delete'))),
          ]),
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
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(f.mode == FtpMode.ftp ? Icons.dns_outlined : Icons.lock_outline),
            const SizedBox(width: 8),
            Expanded(child: Text(tr(f.name), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            Switch(value: running, onChanged: (v) => _toggleFtp(f, v)),
          ]),
          Text(
              '${f.mode.label} • ${tr('port {port}', {'port': f.port})} • ${tr('user {user}', {'user': f.anonymous ? 'anonymous / ${f.username}' : f.username})}'
              '${f.readOnly ? ' • ${tr('read-only')}' : ''}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          if (s?.error != null) Text(s!.error!, style: TextStyle(color: scheme.error)),
          if (running) ...[
            const SizedBox(height: 4),
            SelectableText(url, textDirection: TextDirection.ltr),
            _altAddresses(scheme, f.mode.scheme, f.port, ''),
            Text(tr(s!.connections == 1 ? '{n} connection' : '{n} connections', {'n': s.connections}),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            if (f.mode != FtpMode.ftp)
              Text(tr('Self-signed certificate: accept it in your FTP client.'),
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          ],
          Wrap(alignment: WrapAlignment.end, children: [
            TextButton.icon(onPressed: () => _copy(url, tr('Address copied')), icon: const Icon(Icons.copy, size: 16), label: Text(tr('Copy'))),
            TextButton.icon(onPressed: () => _editFtp(f), icon: const Icon(Icons.edit, size: 16), label: Text(tr('Edit'))),
            TextButton.icon(onPressed: () => _deleteFtp(f), icon: const Icon(Icons.delete_outline, size: 16), label: Text(tr('Delete'))),
          ]),
        ]),
      ),
    );
  }
}
