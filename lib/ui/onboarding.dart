import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../host/host_controller.dart';
import '../l10n.dart';
import '../paths.dart';
import '../settings.dart';
import 'privacy.dart';
import 'splash.dart';

/// Shown once (and again if the policy version changes): choose the language and accept the privacy policy.
/// Nothing starts (servers, ads) before the user accepts.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.paths, required this.settings, required this.boot});
  final AppPaths paths;
  final AppSettings settings;

  /// Creates the host once the policy is accepted.
  final Future<HostController> Function() boot;
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  bool agreed = false;
  bool busy = false;

  void _lang(String c) {
    switchLanguage(c);
    setState(() {});
  }

  Future<void> _accept() async {
    setState(() => busy = true);
    widget.settings
      ..lang = Lang.code
      ..privacyVersion = AppSettings.kPrivacyVersion;
    await widget.settings.save(widget.paths.settingsFile);
    final host = await widget.boot();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => SplashPage(paths: widget.paths, host: host)),
    );
  }

  void _decline() {
    if (Platform.isAndroid) {
      SystemNavigator.pop();
    } else {
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Image.asset('assets/icon.png', width: 56, height: 56,
                      errorBuilder: (_, __, ___) => const Icon(Icons.dns_rounded, size: 48)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(tr('Welcome to PocketServer'), style: Theme.of(context).textTheme.titleLarge)),
                ]),
                const SizedBox(height: 16),
                Text(tr('Language'), style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'en', label: Text('English')),
                    ButtonSegment(value: 'ar', label: Text('العربية')),
                  ],
                  selected: {Lang.code},
                  onSelectionChanged: (s) => _lang(s.first),
                ),
                const SizedBox(height: 16),
                Text(tr('Please read and accept the Privacy Policy to continue.')),
                const SizedBox(height: 8),
                Expanded(
                  child: Card(
                    margin: EdgeInsets.zero,
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                    child: const Scrollbar(
                      child: SingleChildScrollView(padding: EdgeInsets.all(14), child: PrivacyBody()),
                    ),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: agreed,
                  onChanged: busy ? null : (v) => setState(() => agreed = v ?? false),
                  title: Text(tr('I have read and agree to the Privacy Policy')),
                ),
                Row(children: [
                  if (!Platform.isIOS) TextButton(onPressed: busy ? null : _decline, child: Text(tr('Decline'))),
                  const Spacer(),
                  FilledButton(
                    onPressed: (agreed && !busy) ? _accept : null,
                    child: busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(tr('Continue')),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
