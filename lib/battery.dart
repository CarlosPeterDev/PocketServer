import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import 'l10n.dart';
import 'paths.dart';

/// True for the Google Play build (`--dart-define=PLAY_BUILD=true`). That build does not declare
/// REQUEST_IGNORE_BATTERY_OPTIMIZATIONS (Play restricts it), so it opens the battery settings page instead.
const bool kPlayBuild = bool.fromEnvironment('PLAY_BUILD');

Future<bool> batteryUnrestricted() async {
  if (!Platform.isAndroid) return true;
  try {
    return await Permission.ignoreBatteryOptimizations.isGranted;
  } catch (_) {
    return false;
  }
}

Future<void> _openBatterySettings(BuildContext context) async {
  try {
    await const AndroidIntent(action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS').launch();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('Open Settings > Apps > PocketServer > Battery'))));
    }
  }
}

/// Full build: shows the small Android box "Stop optimising battery usage? Deny / Allow".
/// Play build: opens the battery settings page. Returns true when battery is unrestricted afterwards.
Future<bool> requestBatteryExemption(BuildContext context) async {
  if (!Platform.isAndroid) return true;
  if (kPlayBuild) {
    await _openBatterySettings(context);
    return false;
  }
  try {
    final r = await Permission.ignoreBatteryOptimizations.request();
    return r.isGranted;
  } catch (_) {
    if (context.mounted) await _openBatterySettings(context);
    return false;
  }
}

File batteryMarker(AppPaths paths) => File(p.join(paths.dataDir.path, 'no_battery_prompt'));

/// Explains why, then triggers the system "Allow" box. [marker] adds a "Don't ask again" button.
Future<void> showBatteryHelp(BuildContext context, {File? marker}) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.battery_charging_full, size: 36),
      title: Text(tr('Allow background running')),
      content: SingleChildScrollView(
        child: Text(
          '${tr('PocketServer shares your files from this phone, so it has to keep running when the screen is off or the app is in the background. With the default battery setting, Android may stop it after a while to save power, and your FTP, WebDAV and web connections (and any transfer in progress) would stop working.')}\n\n'
          '${kPlayBuild ? tr('Tap Continue, choose PocketServer, then pick Unrestricted (on some phones: No restrictions or Do not optimise).') : tr('Tap Continue, then press Allow in the small Android box that appears. You can change this back at any time in the phone settings.')}',
        ),
      ),
      actions: [
        if (marker != null)
          TextButton(
            onPressed: () {
              try {
                marker.writeAsStringSync('1');
              } catch (_) {}
              Navigator.pop(c, false);
            },
            child: Text(tr("Don't ask again")),
          ),
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Later'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Continue'))),
      ],
    ),
  );
  if (go != true || !context.mounted) return;
  final ok = await requestBatteryExemption(context);
  if (ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Battery is now unrestricted for PocketServer.'))));
  }
}
