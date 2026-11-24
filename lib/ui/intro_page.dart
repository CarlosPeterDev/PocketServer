import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../paths.dart';
import '../settings.dart';

/// Welcome slides: what the app is, that it works without internet, that it is not a spy.
/// Shown once after the privacy screen, and again from Settings.
class IntroPage extends StatefulWidget {
  const IntroPage({super.key, required this.paths, required this.settings, this.next});
  final AppPaths paths;
  final AppSettings settings;

  /// Called when the slides end (replaces this page). null = just close (opened from Settings).
  final void Function(BuildContext context)? next;
  @override
  State<IntroPage> createState() => _IntroPageState();
}

Future<Map<String, dynamic>>? _cache;
Future<Map<String, dynamic>> _loadIntro() => _cache ??= rootBundle
    .loadString('assets/intro.json')
    .then((s) => Map<String, dynamic>.from(jsonDecode(s) as Map));

const _icons = <String, IconData>{
  'dns': Icons.dns_rounded,
  'wifi': Icons.wifi,
  'shield': Icons.verified_user_outlined,
  'steps': Icons.checklist_rounded,
  'pin': Icons.push_pin_outlined,
};

class _IntroPageState extends State<IntroPage> {
  final _ctl = PageController();
  int _page = 0;

  Future<void> _finish() async {
    if (!widget.settings.introSeen) {
      widget.settings.introSeen = true;
      try {
        await widget.settings.save(widget.paths.settingsFile);
      } catch (_) {}
    }
    if (!mounted) return;
    if (widget.next != null) {
      widget.next!(context);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _loadIntro(),
          builder: (context, snap) {
            final d = snap.data;
            if (d == null) return const Center(child: CircularProgressIndicator());
            final slides = ((d[Lang.code] as Map)['slides'] as List).cast<Map>();
            final last = _page == slides.length - 1;
            return Column(children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(onPressed: _finish, child: Text(tr('Skip'))),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _ctl,
                  itemCount: slides.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) => _Slide(slide: slides[i]),
                ),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: last
                        ? _finish
                        : () => _ctl.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                    child: Text(last ? tr('Get started') : tr('Next')),
                  ),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.slide});
  final Map slide;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final points = (slide['points'] as List).cast<String>();
    final text = slide['text'] as String;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (slide['id'] == 'offline')
              const _OfflineDiagram()
            else
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
                child: Icon(_icons[slide['icon']] ?? Icons.info_outline, size: 56, color: cs.onPrimaryContainer),
              ),
            const SizedBox(height: 24),
            Text(slide['title'] as String,
                textAlign: TextAlign.center, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (text.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center, style: t.bodyLarge),
            ],
            if (points.isNotEmpty) ...[
              const SizedBox(height: 16),
              for (final p in points)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.check_circle, size: 20, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(p)),
                  ]),
                ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Phone <-> laptop over WiFi, with the internet crossed out.
class _OfflineDiagram extends StatelessWidget {
  const _OfflineDiagram();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.cloud_off_outlined, size: 34, color: cs.error),
        const SizedBox(width: 8),
        Text(tr('No internet needed'), style: TextStyle(color: cs.error, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 14),
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.smartphone, size: 56, color: cs.primary),
          const SizedBox(width: 6),
          Icon(Icons.arrow_left, color: cs.outline),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
            child: Icon(Icons.wifi, size: 34, color: cs.onPrimaryContainer),
          ),
          Icon(Icons.arrow_right, color: cs.outline),
          const SizedBox(width: 6),
          Icon(Icons.laptop_mac, size: 56, color: cs.primary),
        ]),
      ),
    ]);
  }
}
