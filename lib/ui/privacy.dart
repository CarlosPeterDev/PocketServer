import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';

const String kPrivacyUrl = 'https://github.com/CarlosPeterDev/PocketServer/blob/main/PRIVACY.md';

Future<Map<String, dynamic>>? _cache;
Future<Map<String, dynamic>> _loadPolicy() => _cache ??= rootBundle
    .loadString('assets/privacy.json')
    .then((s) => Map<String, dynamic>.from(jsonDecode(s) as Map));

/// The policy text in the current language (a plain column, put it inside any scroll view).
class PrivacyBody extends StatelessWidget {
  const PrivacyBody({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadPolicy(),
      builder: (context, snap) {
        final d = snap.data;
        if (d == null) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        final doc = Map<String, dynamic>.from(d[Lang.code] as Map);
        final sections = (doc['sections'] as List).cast<Map>();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(doc['title'] as String, style: t.titleLarge),
          const SizedBox(height: 4),
          Text(doc['updated'] as String, style: t.bodySmall),
          const SizedBox(height: 12),
          Text(doc['intro'] as String),
          for (final s in sections) ...[
            const SizedBox(height: 16),
            Text(s['h'] as String, style: t.titleSmall),
            const SizedBox(height: 4),
            SelectableText(s['p'] as String),
          ],
        ]);
      },
    );
  }
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Privacy policy')), actions: [
        IconButton(
          tooltip: tr('Open online'),
          icon: const Icon(Icons.open_in_new),
          onPressed: () => launchUrl(Uri.parse(kPrivacyUrl), mode: LaunchMode.externalApplication),
        ),
      ]),
      body: const SingleChildScrollView(padding: EdgeInsets.all(16), child: PrivacyBody()),
    );
  }
}
