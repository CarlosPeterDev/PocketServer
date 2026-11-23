import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../config.dart';
import '../l10n.dart';
import '../paths.dart';
import '../settings.dart';
import 'server_host.dart';

/// What the UI talks to. Config is always written to the shared config file
/// first and then `reload()` is called.
abstract class HostController {
  Stream<HostStatus> get status;
  HostStatus get current;
  Future<void> reload();
  Future<void> startAll();
  Future<void> stopAll();
  Future<void> startWeb(String id);
  Future<void> stopWeb(String id);
  Future<void> startFtp(String id);
  Future<void> stopFtp(String id);
  Future<void> startDav(String id);
  Future<void> stopDav(String id);
  Future<void> shutdown();

  static Future<HostController> create(AppPaths paths) async {
    if (Platform.isAndroid) return AndroidServiceHost.create();
    final h = LocalHost(ServerHost(paths));
    await h.host.init();
    return h;
  }
}

/// Server runs in the UI isolate (desktop, iOS).
class LocalHost implements HostController {
  LocalHost(this.host);
  final ServerHost host;
  @override
  Stream<HostStatus> get status => host.status;
  @override
  HostStatus get current => host.current;
  @override
  Future<void> reload() => host.reload();
  @override
  Future<void> startAll() => host.startAll();
  @override
  Future<void> stopAll() => host.stopAll();
  @override
  Future<void> startWeb(String id) => host.startWeb(id);
  @override
  Future<void> stopWeb(String id) => host.stopWeb(id);
  @override
  Future<void> startFtp(String id) => host.startFtp(id);
  @override
  Future<void> stopFtp(String id) => host.stopFtp(id);
  @override
  Future<void> startDav(String id) => host.startDav(id);
  @override
  Future<void> stopDav(String id) => host.stopDav(id);
  @override
  Future<void> shutdown() => host.dispose();
}

/// Android: the servers live in a foreground-service isolate so they keep
/// running when the app is closed / in the background.
class AndroidServiceHost implements HostController {
  AndroidServiceHost._(this._svc);
  final FlutterBackgroundService _svc;
  HostStatus _cur = HostStatus();
  final _ctl = StreamController<HostStatus>.broadcast();

  static Future<void> configureService() async {
    final svc = FlutterBackgroundService();
    await svc.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: serviceMain,
        autoStart: false,
        autoStartOnBoot: false, // no boot receiver: servers only start when the user opens the app
        isForegroundMode: true,
        initialNotificationTitle: 'PocketServer',
        initialNotificationContent: tr('Starting servers…'),
        foregroundServiceNotificationId: 4711,
        foregroundServiceTypes: [AndroidForegroundType.specialUse],
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
  }

  static Future<HostController> create() async {
    final svc = FlutterBackgroundService();
    final h = AndroidServiceHost._(svc);
    svc.on('status').listen((e) {
      if (e == null) return;
      h._cur = HostStatus.fromJson(Map<String, dynamic>.from(e));
      h._ctl.add(h._cur);
    });
    if (!await svc.isRunning()) await svc.startService();
    // ask for a fresh status in case the service was already running
    Future.delayed(const Duration(milliseconds: 600), () => svc.invoke('ping'));
    return h;
  }

  @override
  Stream<HostStatus> get status => _ctl.stream;
  @override
  HostStatus get current => _cur;
  void _cmd(String c, [String? id]) => _svc.invoke('cmd', {'c': c, 'id': id});
  @override
  Future<void> reload() async => _cmd('reload');
  @override
  Future<void> startAll() async => _cmd('startAll');
  @override
  Future<void> stopAll() async => _cmd('stopAll');
  @override
  Future<void> startWeb(String id) async => _cmd('startWeb', id);
  @override
  Future<void> stopWeb(String id) async => _cmd('stopWeb', id);
  @override
  Future<void> startFtp(String id) async => _cmd('startFtp', id);
  @override
  Future<void> stopFtp(String id) async => _cmd('stopFtp', id);
  @override
  Future<void> startDav(String id) async => _cmd('startDav', id);
  @override
  Future<void> stopDav(String id) async => _cmd('stopDav', id);
  @override
  Future<void> shutdown() async {
    _svc.invoke('stopService');
  }
}

@pragma('vm:entry-point')
Future<void> serviceMain(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  final paths = await AppPaths.resolve();
  Future<void> applyLang() async {
    final st = await AppSettings.load(paths.settingsFile);
    Lang.set(st.lang ?? Lang.deviceDefault());
  }

  await applyLang();
  final host = ServerHost(paths);
  await host.init();

  void publish(HostStatus s) {
    service.invoke('status', s.toJson());
    if (service is AndroidServiceInstance) {
      final w = s.web.values.where((f) => f.running).length;
      final n = s.ftp.values.where((f) => f.running).length;
      final d = s.dav.values.where((f) => f.running).length;
      final parts = <String>[
        if (w > 0) tr(w == 1 ? '{n} web hub' : '{n} web hubs', {'n': w}),
        if (d > 0) tr('{n} WebDAV', {'n': d}),
        if (n > 0) tr(n == 1 ? '{n} FTP server' : '{n} FTP servers', {'n': n}),
      ];
      service.setForegroundNotificationInfo(
        title: 'PocketServer',
        content: parts.isEmpty ? tr('No server running') : parts.join('  •  '),
      );
    }
  }

  host.status.listen(publish);
  service.on('ping').listen((_) => publish(host.current));
  service.on('stopService').listen((_) async {
    await host.dispose();
    service.stopSelf();
  });
  service.on('cmd').listen((e) async {
    if (e == null) return;
    final id = e['id'] as String?;
    switch (e['c']) {
      case 'reload':
        await applyLang();
        await host.reload();
        publish(host.current); // refresh the notification text (language may have changed)
      case 'startAll':
        await host.startAll();
      case 'stopAll':
        await host.stopAll();
      case 'startWeb':
        if (id != null) await host.startWeb(id);
      case 'stopWeb':
        if (id != null) await host.stopWeb(id);
      case 'startFtp':
        if (id != null) await host.startFtp(id);
      case 'stopFtp':
        if (id != null) await host.stopFtp(id);
      case 'startDav':
        if (id != null) await host.startDav(id);
      case 'stopDav':
        if (id != null) await host.stopDav(id);
    }
  });
  publish(host.current);
}
