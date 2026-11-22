import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../config.dart';
import 'login_guard.dart';
import 'stats.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Minimal but complete FTP / FTPS (explicit + implicit) server.
class FtpRoot {
  const FtpRoot(this.name, this.path);
  final String name;
  final String path;
}

class FtpServer {
  FtpServer(this.cfg, this.roots, {this.tls});

  final FtpServerConfig cfg;
  final List<FtpRoot> roots; // one = plain root, several = merged top-level dirs
  bool get merged => roots.length > 1;
  final SecurityContext? tls;

  ServerSocket? _plain;
  SecureServerSocket? _secure;
  final Set<_FtpSession> _sessions = {};
  static const int maxSessions = 24;

  int get connections => _sessions.length;
  bool get running => _plain != null || _secure != null;

  Future<void> start() async {
    if (cfg.mode != FtpMode.ftp && tls == null) {
      throw StateError('TLS certificate not available');
    }
    if (cfg.mode == FtpMode.ftpsImplicit) {
      final s = await SecureServerSocket.bind(InternetAddress.anyIPv4, cfg.port, tls!, shared: false);
      _secure = s;
      s.listen(_accept, onError: (_) {});
    } else {
      final s = await ServerSocket.bind(InternetAddress.anyIPv4, cfg.port, shared: false);
      _plain = s;
      s.listen(_accept, onError: (_) {});
    }
  }

  void _accept(Socket c) {
    if (_sessions.length >= maxSessions) {
      c.write('421 Too many connections\r\n');
      c.destroy();
      return;
    }
    final s = _FtpSession(this, c, implicitTls: cfg.mode == FtpMode.ftpsImplicit);
    _sessions.add(s);
    Stats.i.ftpConnections++;
    s.start();
  }

  Future<void> stop() async {
    final a = _plain;
    final b = _secure;
    _plain = null;
    _secure = null;
    await a?.close();
    await b?.close();
    for (final s in _sessions.toList()) {
      s.close();
    }
    _sessions.clear();
  }

  void _removed(_FtpSession s) => _sessions.remove(s);
}

class _FtpSession {
  _FtpSession(this.srv, this._ctl, {required bool implicitTls}) : _tls = implicitTls;

  final FtpServer srv;
  Socket _ctl;
  bool _tls;
  StreamSubscription<List<int>>? _sub;
  final List<int> _buf = [];
  Future<void> _chain = Future.value();
  Timer? _idle;
  bool _closed = false;

  String? _user;
  bool _authed = false;
  bool _anon = false;
  String _cwd = '/';
  String? _renameFrom;
  int _rest = 0;
  bool _protP = false;
  ServerSocket? _pasv;
  Completer<Socket>? _pasvConn;
  InternetAddress? _activeHost;
  int _activePort = 0;

  FtpServerConfig get cfg => srv.cfg;
  bool get _readOnly => cfg.readOnly || _anon;

  void start() {
    _attach(_ctl);
    _send('220 PocketServer FTP ready');
    _resetIdle();
  }

  void _attach(Socket s) {
    _sub = s.listen(_onData, onDone: close, onError: (_) => close(), cancelOnError: true);
  }

  void _resetIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(minutes: 15), close);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _idle?.cancel();
    _closePasv();
    try {
      _sub?.cancel();
    } catch (_) {}
    try {
      _ctl.destroy();
    } catch (_) {}
    srv._removed(this);
    if (Stats.i.ftpConnections > 0) Stats.i.ftpConnections--;
  }

  // ── control channel ──────────────────────────────────────────────────────
  void _onData(List<int> data) {
    _resetIdle();
    // drop telnet IAC sequences (e.g. before ABOR)
    for (var i = 0; i < data.length; i++) {
      final b = data[i];
      if (b == 0xFF) {
        if (i + 1 < data.length) {
          final c = data[i + 1];
          i++;
          if (c >= 0xFB && c <= 0xFE) i++;
        }
        continue;
      }
      _buf.add(b);
    }
    while (true) {
      final nl = _buf.indexOf(10);
      if (nl < 0) break;
      final lineBytes = _buf.sublist(0, nl);
      _buf.removeRange(0, nl + 1);
      var line = utf8.decode(lineBytes, allowMalformed: true);
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      if (line.isEmpty) continue;
      _chain = _chain.then((_) => _handle(line)).catchError((Object _) {});
    }
    if (_buf.length > 8192) close();
  }

  void _send(String line) {
    if (_closed) return;
    try {
      _ctl.add(utf8.encode('$line\r\n'));
    } catch (_) {
      close();
    }
  }

  Future<void> _handle(String line) async {
    if (_closed) return;
    final sp = line.indexOf(' ');
    final cmd = (sp < 0 ? line : line.substring(0, sp)).toUpperCase();
    final arg = sp < 0 ? '' : line.substring(sp + 1);

    // commands allowed before login
    switch (cmd) {
      case 'USER':
        if (cfg.mode == FtpMode.ftpsExplicit && !_tls) {
          return _send('530 TLS required: send AUTH TLS first');
        }
        _user = arg;
        _authed = false;
        return _send('331 Password required');
      case 'PASS':
        return _pass(arg);
      case 'AUTH':
        return _auth(arg);
      case 'PBSZ':
        return _send(_tls ? '200 PBSZ=0' : '503 Send AUTH TLS first');
      case 'PROT':
        if (!_tls) return _send('503 Send AUTH TLS first');
        final lvl = arg.toUpperCase();
        if (lvl == 'P') {
          _protP = true;
          return _send('200 Data channel protection: Private');
        }
        if (lvl == 'C') {
          _protP = false;
          return _send('200 Data channel protection: Clear');
        }
        return _send('504 Unsupported protection level');
      case 'FEAT':
        final f = <String>[
          ' UTF8', ' SIZE', ' MDTM', ' REST STREAM', ' EPSV', ' MLST type*;size*;modify*;',
          if (cfg.mode != FtpMode.ftp) ...[' AUTH TLS', ' PBSZ', ' PROT'],
        ];
        return _send('211-Features:\r\n${f.join('\r\n')}\r\n211 End');
      case 'SYST':
        return _send('215 UNIX Type: L8');
      case 'NOOP':
        return _send('200 OK');
      case 'QUIT':
        _send('221 Goodbye');
        Timer(const Duration(milliseconds: 150), close);
        return;
      case 'OPTS':
        return _send(arg.toUpperCase().startsWith('UTF8') ? '200 UTF8 enabled' : '501 Option not supported');
    }
    if (!_authed) return _send('530 Please login with USER and PASS');

    switch (cmd) {
      case 'PWD':
      case 'XPWD':
        return _send('257 "${_cwd.replaceAll('"', '""')}" is the current directory');
      case 'CWD':
      case 'XCWD':
        return _cwdTo(arg);
      case 'CDUP':
      case 'XCUP':
        return _cwdTo('..');
      case 'TYPE':
      case 'MODE':
      case 'STRU':
        return _send('200 OK');
      case 'ALLO':
        return _send('202 Not needed');
      case 'PASV':
        return _pasvCmd(extended: false);
      case 'EPSV':
        return _pasvCmd(extended: true);
      case 'PORT':
        return _port(arg);
      case 'EPRT':
        return _eprt(arg);
      case 'LIST':
        return _list(arg, mode: 'LIST');
      case 'NLST':
        return _list(arg, mode: 'NLST');
      case 'MLSD':
        return _list(arg, mode: 'MLSD');
      case 'MLST':
        return _mlst(arg);
      case 'RETR':
        return _retr(arg);
      case 'STOR':
        return _stor(arg, append: false);
      case 'APPE':
        return _stor(arg, append: true);
      case 'REST':
        final n = int.tryParse(arg);
        if (n == null || n < 0) return _send('501 Bad offset');
        _rest = n;
        return _send('350 Restarting at $n');
      case 'SIZE':
        final f = _realFile(arg);
        if (f == null) return _send('550 Not a file');
        return _send('213 ${f.lengthSync()}');
      case 'MDTM':
        final path = _real(_v(arg));
        if (path == null || FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound) {
          return _send('550 Not found');
        }
        return _send('213 ${_mdtm(File(path).statSync().modified)}');
      case 'DELE':
        return _dele(arg);
      case 'MKD':
      case 'XMKD':
        return _mkd(arg);
      case 'RMD':
      case 'XRMD':
        return _rmd(arg);
      case 'RNFR':
        return _rnfr(arg);
      case 'RNTO':
        return _rnto(arg);
      case 'ABOR':
        return _send('226 No transfer in progress');
      case 'STAT':
        return _send('211 PocketServer FTP: logged in as ${_user ?? ''}');
      case 'SITE':
        return _send('200 OK');
      case 'HELP':
        return _send('214 Standard FTP commands supported');
      default:
        return _send('502 Command not implemented');
    }
  }

  // ── auth / TLS ───────────────────────────────────────────────────────────
  Future<void> _pass(String pw) async {
    final u = _user;
    if (u == null) return _send('503 Send USER first');
    final ip = _ctl.remoteAddress.address;
    if (LoginGuard.i.isLocked(ip)) return _send('530 Too many failed logins, try later');
    final isAnon = cfg.anonymous && (u.toLowerCase() == 'anonymous' || u.toLowerCase() == 'ftp');
    if (isAnon) {
      _authed = true;
      _anon = true;
      Stats.i.event(cfg.id, 'login', 'anonymous');
      return _send('230 Anonymous access granted (read-only)');
    }
    if (_safeEq(u, cfg.username) & _safeEq(pw, cfg.password)) {
      _authed = true;
      _anon = false;
      Stats.i.event(cfg.id, 'login', u);
      LoginGuard.i.ok(ip);
      return _send('230 Login successful');
    }
    Stats.i.event(cfg.id, 'failed', u);
    LoginGuard.i.fail(ip);
    await Future<void>.delayed(const Duration(milliseconds: 600)); // slow brute force
    _send('530 Login incorrect');
  }

  bool _safeEq(String a, String b) {
    final x = utf8.encode(a);
    final y = utf8.encode(b);
    var diff = x.length ^ y.length;
    for (var i = 0; i < x.length && i < y.length; i++) {
      diff |= x[i] ^ y[i];
    }
    return diff == 0;
  }

  Future<void> _auth(String arg) async {
    final m = arg.toUpperCase();
    if (cfg.mode == FtpMode.ftp || srv.tls == null) return _send('502 TLS not available on this server');
    if (_tls) return _send('503 TLS already active');
    if (m != 'TLS' && m != 'SSL' && m != 'TLS-C' && m != 'TLS-P') return _send('504 Unknown AUTH type');
    _send('234 Proceed with TLS negotiation');
    try {
      await _ctl.flush();
      _sub?.pause();
      final secure = await SecureSocket.secureServer(_ctl, srv.tls);
      final old = _sub;
      _ctl = secure;
      _tls = true;
      _buf.clear();
      _attach(secure);
      unawaited(old?.cancel());
    } catch (_) {
      close();
    }
  }

  // ── paths ────────────────────────────────────────────────────────────────
  String _v(String arg) {
    final path = arg.startsWith('/') ? arg : (_cwd == '/' ? '/$arg' : '$_cwd/$arg');
    final parts = <String>[];
    for (final seg in path.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(seg);
      }
    }
    return '/${parts.join('/')}';
  }

  /// Virtual path -> real path (null when hidden / outside the root / virtual root of a merged server).
  String? _real(String vpath) {
    final segs = vpath.split('/').where((s) => s.isNotEmpty).toList();
    if (segs.any((s) => s.startsWith('.') || s.contains('\\') || s.contains('\u0000'))) return null;
    String rootPath;
    var rest = segs;
    if (srv.merged) {
      if (segs.isEmpty) return null;
      final r = srv.roots.where((e) => e.name == segs.first).firstOrNull;
      if (r == null) return null;
      rootPath = r.path;
      rest = segs.sublist(1);
    } else {
      rootPath = srv.roots.first.path;
    }
    final full = p.normalize(p.join(rootPath, p.joinAll(rest.isEmpty ? [''] : rest)));
    final root = p.normalize(rootPath);
    if (full == root || p.isWithin(root, full)) return full;
    return null;
  }

  File? _realFile(String arg) {
    final r = _real(_v(arg));
    if (r == null || !FileSystemEntity.isFileSync(r)) return null;
    return File(r);
  }

  Future<void> _cwdTo(String arg) async {
    final v = _v(arg);
    if (srv.merged && v == '/') {
      _cwd = v;
      return _send('250 Directory changed to /');
    }
    final r = _real(v);
    if (r == null || !FileSystemEntity.isDirectorySync(r)) return _send('550 No such directory');
    _cwd = v;
    _send('250 Directory changed to $v');
  }

  // ── data connections ─────────────────────────────────────────────────────
  void _closePasv() {
    try {
      _pasv?.close();
    } catch (_) {}
    _pasv = null;
    if (_pasvConn != null && !_pasvConn!.isCompleted) {
      _pasvConn!.completeError(StateError('closed'));
    }
    _pasvConn = null;
  }

  Future<void> _pasvCmd({required bool extended}) async {
    _closePasv();
    _activeHost = null;
    try {
      final s = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      _pasv = s;
      final comp = Completer<Socket>();
      _pasvConn = comp;
      s.listen((c) {
        if (!comp.isCompleted) {
          comp.complete(c);
          s.close();
        } else {
          c.destroy();
        }
      });
      if (extended) {
        _send('229 Entering Extended Passive Mode (|||${s.port}|)');
      } else {
        final ip = _ctl.address.type == InternetAddressType.IPv4 ? _ctl.address.address : '127.0.0.1';
        _send('227 Entering Passive Mode (${ip.replaceAll('.', ',')},${s.port >> 8},${s.port & 255})');
      }
    } catch (e) {
      _send('425 Cannot open passive port');
    }
  }

  Future<void> _port(String arg) async {
    final n = arg.split(',').map((e) => int.tryParse(e.trim())).toList();
    if (n.length != 6 || n.any((e) => e == null || e < 0 || e > 255)) return _send('501 Bad PORT');
    return _setActive('${n[0]}.${n[1]}.${n[2]}.${n[3]}', n[4]! * 256 + n[5]!);
  }

  Future<void> _eprt(String arg) async {
    final parts = arg.split(arg.isEmpty ? '|' : arg[0]);
    if (parts.length < 4) return _send('501 Bad EPRT');
    final port = int.tryParse(parts[3]);
    if (port == null) return _send('501 Bad EPRT');
    return _setActive(parts[2], port);
  }

  void _setActive(String host, int port) {
    final peer = _ctl.remoteAddress.address;
    if (host != peer) return _send('501 Active mode only to the control connection address');
    _closePasv();
    _activeHost = InternetAddress(host);
    _activePort = port;
    _send('200 PORT command successful');
  }

  Future<Socket?> _openData() async {
    Socket? s;
    try {
      if (_pasvConn != null) {
        s = await _pasvConn!.future.timeout(const Duration(seconds: 30));
      } else if (_activeHost != null) {
        s = await Socket.connect(_activeHost, _activePort, timeout: const Duration(seconds: 15));
      }
      if (s != null && _tls && _protP && srv.tls != null) {
        s = await SecureSocket.secureServer(s, srv.tls);
      }
    } catch (_) {
      s = null;
    } finally {
      _closePasv();
      _activeHost = null;
    }
    return s;
  }

  // ── listing ──────────────────────────────────────────────────────────────
  Future<void> _list(String arg, {required String mode}) async {
    var a = arg;
    while (a.startsWith('-')) {
      final i = a.indexOf(' ');
      a = i < 0 ? '' : a.substring(i + 1).trimLeft();
    }
    final v = _v(a);
    final r = _real(v);
    final entries = <MapEntry<String, FileSystemEntity>>[]; // display name -> entity
    if (srv.merged && v == '/') {
      for (final root in srv.roots) {
        entries.add(MapEntry(root.name, Directory(root.path)));
      }
    } else {
      if (r == null || FileSystemEntity.typeSync(r) == FileSystemEntityType.notFound) {
        return _send('550 No such file or directory');
      }
      if (FileSystemEntity.isDirectorySync(r)) {
        try {
          for (final e in Directory(r).listSync(followLinks: false)) {
            final n = p.basename(e.path);
            if (!n.startsWith('.')) entries.add(MapEntry(n, e));
          }
        } catch (_) {
          return _send('550 Cannot read directory');
        }
      } else {
        entries.add(MapEntry(p.basename(r), File(r)));
      }
      entries.sort((x, y) => x.key.toLowerCase().compareTo(y.key.toLowerCase()));
    }
    _send('150 Opening data connection');
    final data = await _openData();
    if (data == null) return _send('425 Cannot open data connection');
    final sb = StringBuffer();
    for (final en in entries) {
      FileStat st;
      try {
        st = en.value.statSync();
      } catch (_) {
        continue;
      }
      final name = en.key;
      final isDir = st.type == FileSystemEntityType.directory;
      if (mode == 'NLST') {
        sb.write('$name\r\n');
      } else if (mode == 'MLSD') {
        sb.write('${_facts(st, isDir)} $name\r\n');
      } else {
        sb.write('${_unixLine(st, isDir, name)}\r\n');
      }
    }
    try {
      data.add(utf8.encode(sb.toString()));
      await data.flush();
      await data.close();
      _send('226 Transfer complete');
    } catch (_) {
      data.destroy();
      _send('426 Transfer aborted');
    }
  }

  Future<void> _mlst(String arg) async {
    final v = _v(arg);
    if (srv.merged && v == '/') return _send('250-Listing /\r\n type=dir; /\r\n250 End');
    final r = _real(v);
    if (r == null || FileSystemEntity.typeSync(r) == FileSystemEntityType.notFound) {
      return _send('550 Not found');
    }
    final st = FileStat.statSync(r);
    final isDir = st.type == FileSystemEntityType.directory;
    _send('250-Listing $v\r\n ${_facts(st, isDir)} $v\r\n250 End');
  }

  String _facts(FileStat st, bool isDir) =>
      'type=${isDir ? 'dir' : 'file'};size=${st.size};modify=${_mdtm(st.modified)};';

  String _mdtm(DateTime t) {
    final u = t.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year.toString().padLeft(4, '0')}${two(u.month)}${two(u.day)}${two(u.hour)}${two(u.minute)}${two(u.second)}';
  }

  String _unixLine(FileStat st, bool isDir, String name) {
    final perms = isDir ? (_readOnly ? 'dr-xr-xr-x' : 'drwxr-xr-x') : (_readOnly ? '-r--r--r--' : '-rw-r--r--');
    final t = st.modified;
    final recent = DateTime.now().difference(t).inDays.abs() < 180;
    final when = recent
        ? '${_months[t.month - 1]} ${t.day.toString().padLeft(2)} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
        : '${_months[t.month - 1]} ${t.day.toString().padLeft(2)} ${t.year.toString().padLeft(5)}';
    return '$perms 1 ftp ftp ${st.size.toString().padLeft(12)} $when $name';
  }

  // ── transfers ────────────────────────────────────────────────────────────
  Future<void> _retr(String arg) async {
    final f = _realFile(arg);
    if (f == null) return _send('550 File not found');
    final offset = _rest;
    _rest = 0;
    final len = f.lengthSync();
    if (offset > len) return _send('554 Bad restart offset');
    _send('150 Opening data connection for ${p.basename(f.path)} ($len bytes)');
    final data = await _openData();
    if (data == null) return _send('425 Cannot open data connection');
    try {
      await data.addStream(f.openRead(offset));
      Stats.i.addOut(len - offset, cfg.id);
      Stats.i.event(cfg.id, 'download', p.basename(f.path));
      await data.flush();
      await data.close();
      _send('226 Transfer complete');
    } catch (_) {
      data.destroy();
      _send('426 Transfer aborted');
    }
  }

  Future<void> _stor(String arg, {required bool append}) async {
    if (_readOnly) return _send('550 Permission denied (read-only)');
    final v = _v(arg);
    final r = _real(v);
    if (r == null || v == '/' || FileSystemEntity.isDirectorySync(r)) return _send('553 Invalid file name');
    if (!FileSystemEntity.isDirectorySync(p.dirname(r))) return _send('550 Directory does not exist');
    final rest = _rest;
    _rest = 0;
    final f = File(r);
    final doAppend = append || (rest > 0 && f.existsSync() && f.lengthSync() == rest);
    _send('150 Ready to receive data');
    final data = await _openData();
    if (data == null) return _send('425 Cannot open data connection');
    try {
      final sink = f.openWrite(mode: doAppend ? FileMode.append : FileMode.write);
      var got = 0;
      await sink.addStream(data.map((c) {
        got += c.length;
        return c;
      }));
      await sink.close();
      Stats.i.addIn(got, cfg.id);
      Stats.i.event(cfg.id, 'upload', p.basename(f.path));
      _send('226 Transfer complete');
    } catch (_) {
      data.destroy();
      _send('426 Transfer aborted');
    }
  }

  // ── modifications ────────────────────────────────────────────────────────
  Future<void> _dele(String arg) async {
    if (_readOnly) return _send('550 Permission denied (read-only)');
    final f = _realFile(arg);
    if (f == null) return _send('550 File not found');
    try {
      await f.delete();
      _send('250 Deleted');
    } catch (_) {
      _send('550 Delete failed');
    }
  }

  Future<void> _mkd(String arg) async {
    if (_readOnly) return _send('550 Permission denied (read-only)');
    final v = _v(arg);
    final r = _real(v);
    if (r == null || v == '/') return _send('550 Invalid name');
    try {
      await Directory(r).create(recursive: false);
      _send('257 "$v" created');
    } catch (_) {
      _send('550 Create directory failed');
    }
  }

  Future<void> _rmd(String arg) async {
    if (_readOnly) return _send('550 Permission denied (read-only)');
    final v = _v(arg);
    final r = _real(v);
    if (r == null || v == '/' || !FileSystemEntity.isDirectorySync(r)) return _send('550 No such directory');
    try {
      await Directory(r).delete(recursive: true);
      _send('250 Removed');
    } catch (_) {
      _send('550 Remove failed');
    }
  }

  Future<void> _rnfr(String arg) async {
    if (_readOnly) return _send('550 Permission denied (read-only)');
    final v = _v(arg);
    final r = _real(v);
    if (r == null || v == '/' || FileSystemEntity.typeSync(r) == FileSystemEntityType.notFound) {
      return _send('550 File not found');
    }
    _renameFrom = r;
    _send('350 Ready for RNTO');
  }

  Future<void> _rnto(String arg) async {
    if (_readOnly) return _send('550 Permission denied (read-only)');
    final from = _renameFrom;
    _renameFrom = null;
    if (from == null) return _send('503 Send RNFR first');
    final to = _real(_v(arg));
    if (to == null) return _send('553 Invalid name');
    try {
      if (FileSystemEntity.isDirectorySync(from)) {
        await Directory(from).rename(to);
      } else {
        await File(from).rename(to);
      }
      _send('250 Renamed');
    } catch (_) {
      _send('550 Rename failed');
    }
  }
}
