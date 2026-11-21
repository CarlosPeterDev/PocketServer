import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob TEST ids only. Replace with real ids (and the app id in the manifest / Info.plist) before release.
class AdIds {
  static String get appOpen => Platform.isIOS
      ? 'ca-app-pub-3940256099942544/5575463023'
      : 'ca-app-pub-3940256099942544/9257395921';
  static String get banner => Platform.isIOS
      ? 'ca-app-pub-3940256099942544/2934735716'
      : 'ca-app-pub-3940256099942544/6300978111';
}

bool get adsSupported => Platform.isAndroid || Platform.isIOS;

/// Loads an app-open ad during the splash. Resolves to the loaded ad, or null
/// when it is not ready within [timeout] (then the ad is discarded for good,
/// so it never pops up after the home screen is visible).
class SplashAd {
  AppOpenAd? _ad;
  bool _abandoned = false;

  Future<AppOpenAd?> load(Duration timeout) async {
    final c = Completer<AppOpenAd?>();
    Future<void>(() async {
      try {
        await MobileAds.instance.initialize();
        if (_abandoned) return;
        await AppOpenAd.load(
          adUnitId: AdIds.appOpen,
          request: const AdRequest(),
          adLoadCallback: AppOpenAdLoadCallback(
            onAdLoaded: (ad) {
              if (_abandoned || c.isCompleted) {
                ad.dispose();
              } else {
                _ad = ad;
                c.complete(ad);
              }
            },
            onAdFailedToLoad: (_) {
              if (!c.isCompleted) c.complete(null);
            },
          ),
        );
      } catch (_) {
        if (!c.isCompleted) c.complete(null);
      }
    });
    final t = Timer(timeout, () {
      if (!c.isCompleted) {
        _abandoned = true;
        c.complete(null);
      }
    });
    final r = await c.future;
    t.cancel();
    return r;
  }

  void dispose() {
    _abandoned = true;
    _ad?.dispose();
  }
}

/// Banner shown at the top of the home screen (mobile only).
class TopBanner extends StatefulWidget {
  const TopBanner({super.key});
  @override
  State<TopBanner> createState() => _TopBannerState();
}

class _TopBannerState extends State<TopBanner> {
  BannerAd? _ad;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (!adsSupported) return;
    _ad = BannerAd(
      adUnitId: AdIds.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _ready = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          _ad = null;
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!adsSupported || !_ready || _ad == null) return const SizedBox.shrink();
    return Container(
      alignment: Alignment.center,
      width: _ad!.size.width.toDouble(),
      height: _ad!.size.height.toDouble(),
      child: AdWidget(ad: _ad!),
    );
  }
}
