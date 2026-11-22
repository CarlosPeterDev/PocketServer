import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config.dart';
import '../host/host_controller.dart';
import '../paths.dart';
import 'storage_scan.dart';

/// Live dashboard: traffic, speed chart, per-server stats, storage breakdown, activity.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.cfg, required this.paths, required this.host});
  final AppConfig cfg;
  final AppPaths paths;
  final HostController host;
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  HostStatus st = HostStatus();
  StorageReport? report;
  bool scanning = false;
  double _tileWidth = 160;

  static const catColors = <String, Color>{
    'Video': Color(0xFFE91E63),
    'Audio': Color(0xFF9C27B0),
    'Images': Color(0xFF00BCD4),
    'Documents': Color(0xFF3F51B5),
    'Archives': Color(0xFFFF9800),
    'Apps': Color(0xFF4CAF50),
    'Other': Color(0xFF9E9E9E),
  };

  @override
  void initState() {
    super.initState();
    st = widget.host.current;
    widget.host.status.listen((s) {
      if (mounted) setState(() => st = s);
    });
    _scan();
  }

  Future<void> _scan() async {
    setState(() => scanning = true);
    final cfg = widget.cfg;
    final ids = <String>{kDefaultFolderId, ...cfg.folders.map((f) => f.id)};
    final list = [for (final id in ids) (cfg.nameOf(id), cfg.pathOf(id, widget.paths.defaultStorage.path))];
    try {
      final r = await scanStorage(list);
      if (mounted) setState(() => report = r);
    } catch (_) {}
    if (mounted) setState(() => scanning = false);
  }

  num _n(String k) => (st.stats[k] as num?) ?? 0;
  List<double> _series(String k) => ((st.stats[k] as List?) ?? []).map((e) => (e as num).toDouble()).toList();

  String _nameOfServer(String id) {
    final w = widget.cfg.webHubs.where((e) => e.id == id).firstOrNull;
    if (w != null) return w.name;
    final d = widget.cfg.dav.where((e) => e.id == id).firstOrNull;
    if (d != null) return d.name;
    final f = widget.cfg.ftp.where((e) => e.id == id).firstOrNull;
    return f?.name ?? id;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sIn = _series('sIn'), sOut = _series('sOut');
    final nowIn = sIn.isEmpty ? 0.0 : sIn.last, nowOut = sOut.isEmpty ? 0.0 : sOut.last;
    final running = st.web.values.where((e) => e.running).length +
        st.ftp.values.where((e) => e.running).length +
        st.dav.values.where((e) => e.running).length;
    final total = running + 0;
    final outBy = Map<String, dynamic>.from((st.stats['outBy'] as Map?) ?? {});
    final inBy = Map<String, dynamic>.from((st.stats['inBy'] as Map?) ?? {});
    final servers = {...outBy.keys, ...inBy.keys};
    final events = ((st.stats['events'] as List?) ?? []).cast<Map>();

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard'), actions: [
        IconButton(
          tooltip: 'Rescan storage',
          icon: scanning
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh),
          onPressed: scanning ? null : _scan,
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        LayoutBuilder(builder: (context, c) {
          final cols = math.max(2, (c.maxWidth / 190).floor());
          _tileWidth = (c.maxWidth - 12 * (cols - 1)) / cols;
          return Wrap(spacing: 12, runSpacing: 12, children: [
          _tile(Icons.dns_outlined, '$total', 'Servers running', cs.primary),
          _tile(Icons.people_alt_outlined, '${_n('conns')}', 'FTP connections', cs.tertiary),
          _tile(Icons.download_outlined, fmtBytes(_n('out')), 'Sent (session)', const Color(0xFFE91E63)),
          _tile(Icons.upload_outlined, fmtBytes(_n('in')), 'Received (session)', const Color(0xFF4CAF50)),
          _tile(Icons.http, '${_n('req')}', 'Web requests', cs.secondary),
          _tile(Icons.gpp_maybe_outlined, '${_n('failed')}', 'Failed logins', cs.error),
        ]);
        }),
        const SizedBox(height: 20),
        _section('Live speed (last 60 s)'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              Row(children: [
                _dot(const Color(0xFFE91E63)),
                Text(' Send ${fmtBytes(nowOut)}/s    '),
                _dot(const Color(0xFF4CAF50)),
                Text(' Receive ${fmtBytes(nowIn)}/s'),
              ]),
              const SizedBox(height: 10),
              SizedBox(
                height: 140,
                width: double.infinity,
                child: CustomPaint(painter: _LinePainter(sOut, sIn, cs.outlineVariant)),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        _section('Traffic per server'),
        if (servers.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No traffic yet.')))
        else
          Card(
            child: Column(children: [
              for (final id in servers)
                ListTile(
                  dense: true,
                  title: Text(_nameOfServer(id)),
                  subtitle: Text('Sent ${fmtBytes((outBy[id] as num?) ?? 0)}   •   Received ${fmtBytes((inBy[id] as num?) ?? 0)}'),
                ),
            ]),
          ),
        const SizedBox(height: 20),
        _section('Storage'),
        _storage(cs),
        const SizedBox(height: 20),
        _section('Recent activity'),
        if (events.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Nothing yet.')))
        else
          Card(
            child: Column(children: [
              for (final e in events.take(25)) _eventTile(e, cs),
            ]),
          ),
      ]),
    );
  }

  Widget _eventTile(Map e, ColorScheme cs) {
    final k = e['k'] as String? ?? '';
    final icon = switch (k) {
      'upload' => Icons.upload,
      'download' => Icons.download,
      'login' => Icons.login,
      'failed' => Icons.error_outline,
      _ => Icons.info_outline,
    };
    final t = DateTime.fromMillisecondsSinceEpoch((e['t'] as num).toInt());
    String two(int n) => n.toString().padLeft(2, '0');
    return ListTile(
      dense: true,
      leading: Icon(icon, color: k == 'failed' ? cs.error : cs.primary, size: 20),
      title: Text('${k[0].toUpperCase()}${k.substring(1)}: ${e['x']}', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(_nameOfServer(e['s'] as String? ?? '')),
      trailing: Text('${two(t.hour)}:${two(t.minute)}:${two(t.second)}', style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _storage(ColorScheme cs) {
    final r = report;
    if (r == null) {
      return const Card(child: Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())));
    }
    final cats = r.byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${fmtBytes(r.totalBytes)} in ${r.files} files, ${r.folders} folders${r.truncated ? ' (partial scan)' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (r.totalBytes > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 14,
                child: Row(children: [
                  for (final c in cats)
                    Expanded(
                      flex: math.max(1, (c.value * 1000 / r.totalBytes).round()),
                      child: Container(color: catColors[c.key]),
                    ),
                ]),
              ),
            ),
          const SizedBox(height: 10),
          for (final c in cats)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                _dot(catColors[c.key] ?? Colors.grey),
                const SizedBox(width: 8),
                Expanded(child: Text('${c.key}  (${r.countByCategory[c.key] ?? 0})')),
                Text(fmtBytes(c.value)),
              ]),
            ),
          if (r.largest.isNotEmpty) ...[
            const Divider(height: 24),
            Text('Largest files', style: Theme.of(context).textTheme.labelLarge),
            for (final f in r.largest)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(f.folder),
                trailing: Text(fmtBytes(f.size)),
              ),
          ],
        ]),
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _dot(Color c) => Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle));

  Widget _tile(IconData i, String v, String l, Color c) {
    return SizedBox(
      width: _tileWidth,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(i, color: c),
            const SizedBox(height: 8),
            Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            Text(l, style: const TextStyle(fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.a, this.b, this.grid);
  final List<double> a, b;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gp);
    }
    final maxV = math.max(1024.0, [...a, ...b].fold<double>(0, math.max));
    void line(List<double> d, Color c) {
      if (d.length < 2) return;
      final path = Path();
      for (var i = 0; i < d.length; i++) {
        final x = size.width * i / 59;
        final y = size.height - (d[i] / maxV) * (size.height - 4) - 2;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round,
      );
    }

    line(a, const Color(0xFFE91E63));
    line(b, const Color(0xFF4CAF50));
    final tp = TextPainter(
      text: TextSpan(text: '${fmtBytes(maxV)}/s', style: TextStyle(fontSize: 10, color: grid)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(2, 0));
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => true;
}
