import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../config.dart';
import '../paths.dart';
import 'server_host.dart';

/// What the UI talks to. Config is always written to the shared config file
/// first and then `reload()` is called.
abstract class HostController {
  Stream<HostStatus> get status;
  HostStatus get current;
  Future<void> reload();
  Future<void> startAll();
  Future<void> stopAll();
  Future<void> startWeb();
  Future<void> stopWeb();
  Future<void> startFtp(String id);
  Future<void> stopFtp(String id);
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
  Future<void> startWeb() => host.startWeb();
  @override
  Future<void> stopWeb() => host.stopWeb();
  @override
  Future<void> startFtp(String id) => host.startFtp(id);
  @override
  Future<void> stopFtp(String id) => host.stopFtp(id);
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
        isForegroundMode: true,
        initialNotificationTitle: 'InfinityShare',
        initialNotificationContent: 'Starting servers…',
        foregroundServiceNotificationId: 4711,
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
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
  Future<void> startWeb() async => _cmd('startWeb');
  @override
  Future<void> stopWeb() async => _cmd('stopWeb');
  @override
  Future<void> startFtp(String id) async => _cmd('startFtp', id);
  @override
  Future<void> stopFtp(String id) async => _cmd('stopFtp', id);
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
  final host = ServerHost(paths);
  await host.init();

  void publish(HostStatus s) {
    service.invoke('status', s.toJson());
    if (service is AndroidServiceInstance) {
      final web = s.webRunning;
      final n = s.ftp.values.where((f) => f.running).length;
      final ip = s.ips.isEmpty ? '' : s.ips.first;
      final parts = <String>[
        if (web) 'Web http://$ip:${host.cfg.webPort}',
        if (n > 0) '$n FTP server${n == 1 ? '' : 's'}',
      ];
      service.setForegroundNotificationInfo(
        title: 'InfinityShare',
        content: parts.isEmpty ? 'No server running' : parts.join('  •  '),
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
        await host.reload();
      case 'startAll':
        await host.startAll();
      case 'stopAll':
        await host.stopAll();
      case 'startWeb':
        await host.startWeb();
      case 'stopWeb':
        await host.stopWeb();
      case 'startFtp':
        if (id != null) await host.startFtp(id);
      case 'stopFtp':
        if (id != null) await host.stopFtp(id);
    }
  });
  publish(host.current);
}
