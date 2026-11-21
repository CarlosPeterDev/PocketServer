import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config.dart';
import '../paths.dart';
import 'ftp_server.dart';
import 'share_store.dart';
import 'tls_cert.dart';
import 'web_server.dart';

/// Owns the web server and all FTP/FTPS servers. Runs either inside the UI
/// isolate (desktop / iOS) or inside the Android foreground-service isolate.
class ServerHost {
  ServerHost(this.paths);

  final AppPaths paths;
  late final TlsCert _tls = TlsCert(paths.certDir);
  AppConfig cfg = AppConfig();
  WebServer? _web;
  String? _webError;
  final Map<String, FtpServer> _ftp = {};
  final Map<String, String> _ftpErr = {};
  List<String> _ips = [];
  final _ctl = StreamController<HostStatus>.broadcast();
  Timer? _tick;

  Stream<HostStatus> get status => _ctl.stream;

  HostStatus get current => HostStatus(
        webRunning: _web?.running ?? false,
        webError: _webError,
        ips: _ips,
        ftp: {
          for (final f in cfg.ftp)
            f.id: FtpStatus(
              running: _ftp[f.id]?.running ?? false,
              error: _ftpErr[f.id],
              connections: _ftp[f.id]?.connections ?? 0,
            ),
        },
      );

  void _emit() {
    if (!_ctl.isClosed) _ctl.add(current);
  }

  Future<void> init() async {
    cfg = await AppConfig.load(paths.configFile);
    _ips = await localIps();
    _tick = Timer.periodic(const Duration(seconds: 3), (_) async {
      _ips = await localIps();
      _emit();
    });
    // auto-start what the user enabled
    if (cfg.webEnabled) await startWeb();
    for (final f in cfg.ftp.where((e) => e.enabled)) {
      await startFtp(f.id);
    }
    _emit();
  }

  /// Re-read config from disk (UI saved it). Restarts running servers whose
  /// settings changed and stops those that were deleted.
  Future<void> reload() async {
    final old = cfg;
    cfg = await AppConfig.load(paths.configFile);
    final webChanged = old.webPort != cfg.webPort || old.storageDir != cfg.storageDir;
    final storageChanged = old.storageDir != cfg.storageDir;
    if (_web?.running ?? false) {
      if (webChanged) {
        await stopWeb();
        await startWeb();
      }
    }
    for (final id in _ftp.keys.toList()) {
      final nf = cfg.ftp.where((e) => e.id == id).firstOrNull;
      final of = old.ftp.where((e) => e.id == id).firstOrNull;
      if (nf == null) {
        await stopFtp(id, keepErr: false);
      } else if (storageChanged || of == null || jsonEncode(of.toJson()) != jsonEncode(nf.toJson())) {
        await stopFtp(id);
        await startFtp(id);
      }
    }
    _emit();
  }

  Future<void> startWeb() async {
    if (_web?.running ?? false) return;
    try {
      final root = paths.storageFor(cfg);
      await Directory(root).create(recursive: true);
      final w = WebServer(ShareStore(root), cfg.webPort);
      await w.start();
      _web = w;
      _webError = null;
    } catch (e) {
      _web = null;
      _webError = _explain(e, cfg.webPort);
    }
    _emit();
  }

  Future<void> stopWeb() async {
    await _web?.stop();
    _web = null;
    _webError = null;
    _emit();
  }

  Future<void> startFtp(String id) async {
    final c = cfg.ftp.where((e) => e.id == id).firstOrNull;
    if (c == null || (_ftp[id]?.running ?? false)) return;
    try {
      final root = paths.storageFor(cfg);
      await Directory(root).create(recursive: true);
      final ctx = c.mode == FtpMode.ftp ? null : await _tls.context();
      final s = FtpServer(c.copy(), root, tls: ctx);
      await s.start();
      _ftp[id] = s;
      _ftpErr.remove(id);
    } catch (e) {
      _ftp.remove(id);
      _ftpErr[id] = _explain(e, c.port);
    }
    _emit();
  }

  Future<void> stopFtp(String id, {bool keepErr = false}) async {
    await _ftp.remove(id)?.stop();
    if (!keepErr) _ftpErr.remove(id);
    _emit();
  }

  Future<void> startAll() async {
    await startWeb();
    for (final f in cfg.ftp) {
      await startFtp(f.id);
    }
  }

  Future<void> stopAll() async {
    await stopWeb();
    for (final id in _ftp.keys.toList()) {
      await stopFtp(id);
    }
  }

  bool get anyRunning => (_web?.running ?? false) || _ftp.values.any((e) => e.running);

  Future<void> dispose() async {
    _tick?.cancel();
    await stopAll();
    await _ctl.close();
  }

  String _explain(Object e, int port) {
    if (e is SocketException) {
      final m = e.osError?.message ?? e.message;
      if (m.toLowerCase().contains('in use')) return 'Port $port is already in use';
      if (m.toLowerCase().contains('permission') || m.toLowerCase().contains('denied')) {
        return 'No permission to use port $port (ports below 1024 need admin rights)';
      }
      return m;
    }
    return e.toString();
  }
}
