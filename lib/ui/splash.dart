import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads.dart';
import '../host/host_controller.dart';
import '../paths.dart';
import 'home.dart';

/// ~3 s loading screen. Tries to load an app-open ad; if it is ready in time it
/// is shown, otherwise the app just continues (the ad is dropped, never shown later).
class SplashPage extends StatefulWidget {
  const SplashPage({super.key, required this.paths, required this.host});
  final AppPaths paths;
  final HostController host;
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final _splashAd = SplashAd();
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (!adsSupported) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      return _home();
    }
    final started = DateTime.now();
    final ad = await _splashAd.load(const Duration(seconds: 3));
    if (ad == null) {
      // keep the splash for the remaining time so it always feels like ~3 s
      final left = const Duration(seconds: 3) - DateTime.now().difference(started);
      if (left > Duration.zero) await Future<void>.delayed(left);
      return _home();
    }
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _home();
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        _home();
      },
    );
    if (!mounted) return;
    ad.show();
  }

  void _home() {
    if (_gone || !mounted) return;
    _gone = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => HomePage(paths: widget.paths, host: widget.host)),
    );
  }

  @override
  void dispose() {
    _splashAd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        color: const Color(0xFF001450),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Image.asset('assets/icon.png', width: 220, height: 220, errorBuilder: (_, __, ___) => const Icon(Icons.dns_rounded, size: 96, color: Colors.white)),
            const SizedBox(height: 32),
            SizedBox(
                width: 140,
                child: LinearProgressIndicator(color: Colors.white, backgroundColor: cs.primary.withOpacity(0.3))),
          ]),
        ),
      ),
    );
  }
}
