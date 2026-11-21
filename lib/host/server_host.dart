import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../config.dart';
import '../paths.dart';
import 'ftp_server.dart';
import 'share_store.dart';
import 'stats.dart';
import 'tls_cert.dart';
import 'web_server.dart';

/// Owns every web hub and FTP/FTPS server. Runs either inside the UI isolate
/// (desktop / iOS) or inside the Android foreground-service isolate.
class ServerHost {
  ServerHost(this.paths);

  final AppPaths paths;
  late final TlsCert _tls = TlsCert(paths.certDir);
  AppConfig cfg = AppConfig();
  final Map<String, WebServer> _web = {};
  final Map<String, String> _webErr = {};
  final Map<String, FtpServer> _ftp = {};
  final Map<String, String> _ftpErr = {};
  List<String> _ips = [];
  final _ctl = StreamController<HostStatus>.broadcast();
  Timer? _tick;

  Stream<HostStatus> get status => _ctl.stream;

  HostStatus get current => HostStatus(
        ips: _ips,
        stats: Stats.i.toJson(),
        web: {
          for (final w in cfg.webHubs)
            w.id: FtpStatus(running: _web[w.id]?.running ?? false, error: _webErr[w.id]),
        },
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
    var n = 0;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) async {
      Stats.i.sample();
      if (n++ % 5 == 0) _ips = await localIps();
      _emit();
    });
    for (final w in cfg.webHubs.where((e) => e.enabled)) {
      await startWeb(w.id);
    }
    for (final f in cfg.ftp.where((e) => e.enabled)) {
      await startFtp(f.id);
    }
    _emit();
  }

  String _dirOf(String folderId) => cfg.pathOf(folderId, paths.defaultStorage.path);

  /// Re-read config from disk (UI saved it). Restarts running servers whose
  /// settings (or folders) changed and stops those that were deleted.
  Future<void> reload() async {
    final old = cfg;
    cfg = await AppConfig.load(paths.configFile);
    final oldFolders = {for (final f in old.folders) f.id: f.path};
    final newFolders = {for (final f in cfg.folders) f.id: f.path};
    bool folderChanged(Iterable<String> ids) => ids.any((i) => oldFolders[i] != newFolders[i]);

    for (final id in _web.keys.toList()) {
      final nw = cfg.webHubs.where((e) => e.id == id).firstOrNull;
      final ow = old.webHubs.where((e) => e.id == id).firstOrNull;
      if (nw == null) {
        await stopWeb(id);
      } else if (ow == null ||
          jsonEncode(ow.toJson()) != jsonEncode(nw.toJson()) ||
          folderChanged([nw.folderId])) {
        await stopWeb(id);
        await startWeb(id);
      }
    }
    for (final id in _ftp.keys.toList()) {
      final nf = cfg.ftp.where((e) => e.id == id).firstOrNull;
      final of = old.ftp.where((e) => e.id == id).firstOrNull;
      if (nf == null) {
        await stopFtp(id);
      } else if (of == null ||
          jsonEncode(of.toJson()) != jsonEncode(nf.toJson()) ||
          folderChanged(nf.folderIds)) {
        await stopFtp(id);
        await startFtp(id);
      }
    }
    _emit();
  }

  Future<void> startWeb(String id) async {
    final c = cfg.webHubs.where((e) => e.id == id).firstOrNull;
    if (c == null || (_web[id]?.running ?? false)) return;
    try {
      final root = _dirOf(c.folderId);
      await Directory(root).create(recursive: true);
      final w = WebServer(ShareStore(root), c.port, id: c.id);
      await w.start();
      _web[id] = w;
      _webErr.remove(id);
    } catch (e) {
      _web.remove(id);
      _webErr[id] = _explain(e, c.port);
    }
    _emit();
  }

  Future<void> stopWeb(String id) async {
    await _web.remove(id)?.stop();
    _webErr.remove(id);
    _emit();
  }

  List<FtpRoot> _rootsOf(FtpServerConfig c) {
    final ids = c.folderIds.isEmpty ? [kDefaultFolderId] : c.folderIds;
    final used = <String>{};
    final out = <FtpRoot>[];
    for (final id in ids) {
      var name = cfg.nameOf(id).replaceAll('/', '_');
      if (name.startsWith('.')) name = '_$name';
      var n = name;
      var i = 2;
      while (!used.add(n)) {
        n = '$name ($i)';
        i++;
      }
      out.add(FtpRoot(n, p.normalize(_dirOf(id))));
    }
    return out;
  }

  Future<void> startFtp(String id) async {
    final c = cfg.ftp.where((e) => e.id == id).firstOrNull;
    if (c == null || (_ftp[id]?.running ?? false)) return;
    try {
      final roots = _rootsOf(c);
      for (final r in roots) {
        await Directory(r.path).create(recursive: true);
      }
      final ctx = c.mode == FtpMode.ftp ? null : await _tls.context();
      final s = FtpServer(c.copy(), roots, tls: ctx);
      await s.start();
      _ftp[id] = s;
      _ftpErr.remove(id);
    } catch (e) {
      _ftp.remove(id);
      _ftpErr[id] = _explain(e, c.port);
    }
    _emit();
  }

  Future<void> stopFtp(String id) async {
    await _ftp.remove(id)?.stop();
    _ftpErr.remove(id);
    _emit();
  }

  Future<void> startAll() async {
    for (final w in cfg.webHubs) {
      await startWeb(w.id);
    }
    for (final f in cfg.ftp) {
      await startFtp(f.id);
    }
  }

  Future<void> stopAll() async {
    for (final id in _web.keys.toList()) {
      await stopWeb(id);
    }
    for (final id in _ftp.keys.toList()) {
      await stopFtp(id);
    }
  }

  Future<void> dispose() async {
    _tick?.cancel();
    await stopAll();
    await _ctl.close();
  }

  String _explain(Object e, int port) {
    if (e is SocketException) {
      final m = (e.osError?.message ?? e.message).toLowerCase();
      if (m.contains('in use')) return 'Port $port is already in use';
      if (m.contains('permission') || m.contains('denied')) {
        return 'No permission for port $port (ports below 1024 need admin rights) or folder';
      }
      return e.osError?.message ?? e.message;
    }
    if (e is FileSystemException) return 'Cannot use folder: ${e.osError?.message ?? e.message}';
    return e.toString();
  }
}
