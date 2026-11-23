import 'dart:io';

import 'package:flutter/material.dart';

import '../ads.dart';
import '../battery.dart';
import '../host/host_controller.dart';
import '../l10n.dart';
import '../paths.dart';
import '../settings.dart';
import 'help_page.dart';
import 'privacy.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.paths, required this.host});
  final AppPaths paths;
  final HostController host;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool? unrestricted;
  bool adOptions = false;

  @override
  void initState() {
    super.initState();
    _checkBattery();
    AdsGate.privacyOptionsRequired().then((v) {
      if (mounted) setState(() => adOptions = v);
    });
  }

  Future<void> _checkBattery() async {
    if (!Platform.isAndroid) return;
    final u = await batteryUnrestricted();
    if (mounted) setState(() => unrestricted = u);
  }

  Future<void> _setLang(String c) async {
    if (c == Lang.code) return;
    switchLanguage(c);
    final s = await AppSettings.load(widget.paths.settingsFile);
    s.lang = c;
    await s.save(widget.paths.settingsFile);
    await widget.host.reload(); // lets the background service refresh its notification text
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Settings'))),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 4),
          child: Text(tr('Language'), style: Theme.of(context).textTheme.titleSmall),
        ),
        RadioListTile<String>(
          value: 'en',
          groupValue: Lang.code,
          title: const Text('English'),
          onChanged: (v) => _setLang(v!),
        ),
        RadioListTile<String>(
          value: 'ar',
          groupValue: Lang.code,
          title: const Text('العربية'),
          onChanged: (v) => _setLang(v!),
        ),
        const Divider(),
        if (Platform.isAndroid)
          ListTile(
            leading: const Icon(Icons.battery_saver_outlined),
            title: Text(tr('Keep running in the background')),
            subtitle: Text(unrestricted == null
                ? ''
                : unrestricted!
                    ? tr('Battery is unrestricted')
                    : tr('Battery is restricted: Android may stop the servers')),
            onTap: () async {
              await showBatteryHelp(context);
              await _checkBattery();
            },
          ),
        ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: Text(tr('How to use PocketServer')),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => HelpPage(host: widget.host))),
        ),
        if (adOptions)
          ListTile(
            leading: const Icon(Icons.ads_click),
            title: Text(tr('Ad privacy choices')),
            onTap: AdsGate.showPrivacyOptions,
          ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: Text(tr('Privacy policy')),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PrivacyPage())),
        ),
      ]),
    );
  }
}
