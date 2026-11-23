import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../host/host_controller.dart';
import '../l10n.dart';

Future<Map<String, dynamic>>? _cache;
Future<Map<String, dynamic>> _loadHelp() => _cache ??= rootBundle
    .loadString('assets/help.json')
    .then((s) => Map<String, dynamic>.from(jsonDecode(s) as Map));

const _icons = <String, IconData>{
  'lightbulb': Icons.lightbulb_outline,
  'wifi': Icons.wifi,
  'web': Icons.language,
  'dns': Icons.dns_outlined,
  'storage': Icons.storage_outlined,
  'folder': Icons.folder_open,
  'battery': Icons.battery_saver_outlined,
  'shield': Icons.shield_outlined,
  'help': Icons.help_outline,
};

/// Simple, non-technical guide: what each server type is, how to connect, WiFi / hotspot.
class HelpPage extends StatelessWidget {
  const HelpPage({super.key, required this.host, this.topic});
  final HostController host;

  /// Topic id to open first (start, wifi, web, ftp, webdav, folders, background, safety, trouble).
  final String? topic;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ips = host.current.ips;
    return Scaffold(
      appBar: AppBar(title: Text(tr('How to use PocketServer'))),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _loadHelp(),
        builder: (context, snap) {
          final d = snap.data;
          if (d == null) return const Center(child: CircularProgressIndicator());
          final topics = ((d[Lang.code] as Map)['topics'] as List).cast<Map>();
          return ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              color: cs.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.router_outlined, color: cs.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Text(tr('Addresses of this device'),
                        style: TextStyle(fontWeight: FontWeight.w600, color: cs.onPrimaryContainer)),
                  ]),
                  const SizedBox(height: 6),
                  if (ips.isEmpty)
                    Text(tr('No network found. Connect to WiFi or turn on the Hotspot.'),
                        style: TextStyle(color: cs.onPrimaryContainer))
                  else
                    for (final ip in ips)
                      SelectableText(ip,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onPrimaryContainer)),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            for (final t in topics)
              Card(
                child: ExpansionTile(
                  key: PageStorageKey<String>('${Lang.code}-${t['id']}'),
                  initiallyExpanded: t['id'] == topic,
                  leading: Icon(_icons[t['icon']] ?? Icons.info_outline),
                  title: Text(t['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                  childrenPadding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t['intro'] as String),
                    const SizedBox(height: 10),
                    for (final (i, s) in (t['steps'] as List).cast<String>().indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          CircleAvatar(radius: 11, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                          const SizedBox(width: 10),
                          Expanded(child: Text(s)),
                        ]),
                      ),
                    if ((t['tip'] as String).isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.tips_and_updates_outlined, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text('${tr('Tip')}: ${t['tip']}')),
                        ]),
                      ),
                    ],
                  ],
                ),
              ),
          ]);
        },
      ),
    );
  }
}
