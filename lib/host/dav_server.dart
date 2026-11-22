import 'dart:convert';
import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../config.dart';
import 'login_guard.dart';
import 'stats.dart';

String _x(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// WebDAV server (class 1+2 faked locks so Windows / macOS / Android clients can write).
/// Mount it as a network drive: Windows "Map network drive", macOS "Connect to server", Linux davfs2, any WebDAV app.
class DavServer {
  DavServer(this.cfg, this.rootPath);
  final DavConfig cfg;
  final String rootPath;
  HttpServer? _server;
  int connections = 0;

  bool get running => _server != null;

  Future<void> start() async {
    final s = await HttpServer.bind(InternetAddress.anyIPv4, cfg.port);
    s.idleTimeout = const Duration(seconds: 60);
    _server = s;
    s.listen((req) async {
      connections++;
      try {
        await _handle(req);
      } catch (_) {
        try {
          req.response.statusCode = 500;
          await req.response.close();
        } catch (_) {}
      } finally {
        connections--;
      }
    }, onError: (_) {});
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }

  // ── helpers ──
  String? _map(String urlPath) {
    final segs = urlPath.split('/').where((e) => e.isNotEmpty).map(Uri.decodeComponent).toList();
    if (segs.any((e) => e == '..' || e == '.' || e.startsWith('.') || e.contains('\\') || e.contains('\u0000'))) {
      return null;
    }
    final full = p.normalize(p.join(rootPath, p.joinAll(segs.isEmpty ? [''] : segs)));
    final root = p.normalize(rootPath);
    return (full == root || p.isWithin(root, full)) ? full : null;
  }

  String _href(String full, bool dir) {
    var rel = p.relative(full, from: rootPath);
    if (rel == '.') rel = '';
    final parts = rel.isEmpty ? <String>[] : p.split(rel);
    final h = '/${parts.map(Uri.encodeComponent).join('/')}';
    return dir && !h.endsWith('/') ? '$h/' : h;
  }

  bool _authed(HttpRequest req) {
    final h = req.headers.value('authorization');
    if (h == null || !h.toLowerCase().startsWith('basic ')) return false;
    try {
      final d = utf8.decode(base64.decode(h.substring(6).trim()));
      final i = d.indexOf(':');
      if (i < 0) return false;
      return _eq(d.substring(0, i), cfg.username) & _eq(d.substring(i + 1), cfg.password);
    } catch (_) {
      return false;
    }
  }

  bool _eq(String a, String b) {
    final x = utf8.encode(a), y = utf8.encode(b);
    var diff = x.length ^ y.length;
    for (var i = 0; i < x.length && i < y.length; i++) {
      diff |= x[i] ^ y[i];
    }
    return diff == 0;
  }

  Future<void> _status(HttpRequest req, int code, [String? body, String type = 'text/plain; charset=utf-8']) async {
    final r = req.response;
    r.statusCode = code;
    if (body != null) {
      r.headers.contentType = ContentType.parse(type);
      r.add(utf8.encode(body));
    }
    await r.close();
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    final ip = req.connectionInfo?.remoteAddress.address ?? '';
    res.headers.set('DAV', '1, 2');
    res.headers.set('MS-Author-Via', 'DAV');
    if (LoginGuard.i.isLocked(ip)) return _status(req, 429, 'Too many failed logins. Try again later.');
    if (req.method != 'OPTIONS' || req.headers.value('authorization') != null) {
      if (!_authed(req)) {
        if (req.headers.value('authorization') != null) {
          LoginGuard.i.fail(ip);
          Stats.i.event(cfg.id, 'failed', ip);
        }
        res.headers.set('WWW-Authenticate', 'Basic realm="${cfg.name.replaceAll('"', '')}"');
        return _status(req, 401, 'Authentication required');
      }
      LoginGuard.i.ok(ip);
    }
    Stats.i.requests++;

    final target = _map(req.uri.path);
    final m = req.method.toUpperCase();
    const writes = {'PUT', 'DELETE', 'MKCOL', 'MOVE', 'COPY', 'PROPPATCH'};
    if (m == 'OPTIONS') {
      res.headers.set('Allow', 'OPTIONS, GET, HEAD, PUT, DELETE, MKCOL, MOVE, COPY, PROPFIND, PROPPATCH, LOCK, UNLOCK');
      return _status(req, 200);
    }
    if (target == null) return _status(req, 403, 'Forbidden');
    if (cfg.readOnly && writes.contains(m)) return _status(req, 403, 'Read-only server');

    switch (m) {
      case 'PROPFIND':
        return _propfind(req, target);
      case 'PROPPATCH':
        return _status(
            req,
            207,
            '<?xml version="1.0" encoding="utf-8"?><D:multistatus xmlns:D="DAV:"><D:response><D:href>${_x(req.uri.path)}</D:href>'
            '<D:propstat><D:prop/><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response></D:multistatus>',
            'application/xml; charset=utf-8');
      case 'GET':
      case 'HEAD':
        return _get(req, target, head: m == 'HEAD');
      case 'PUT':
        return _put(req, target);
      case 'MKCOL':
        if (FileSystemEntity.typeSync(target) != FileSystemEntityType.notFound) return _status(req, 405);
        if (!Directory(p.dirname(target)).existsSync()) return _status(req, 409);
        await Directory(target).create();
        return _status(req, 201);
      case 'DELETE':
        return _delete(req, target);
      case 'MOVE':
      case 'COPY':
        return _moveCopy(req, target, move: m == 'MOVE');
      case 'LOCK':
        final tok = 'opaquelocktoken:${DateTime.now().microsecondsSinceEpoch}';
        res.headers.set('Lock-Token', '<$tok>');
        return _status(
            req,
            200,
            '<?xml version="1.0" encoding="utf-8"?><D:prop xmlns:D="DAV:"><D:lockdiscovery><D:activelock>'
            '<D:locktype><D:write/></D:locktype><D:lockscope><D:exclusive/></D:lockscope><D:depth>0</D:depth>'
            '<D:timeout>Second-3600</D:timeout><D:locktoken><D:href>$tok</D:href></D:locktoken>'
            '</D:activelock></D:lockdiscovery></D:prop>',
            'application/xml; charset=utf-8');
      case 'UNLOCK':
        return _status(req, 204);
      default:
        return _status(req, 405);
    }
  }

  Future<void> _propfind(HttpRequest req, String target) async {
    await req.drain<void>();
    final type = FileSystemEntity.typeSync(target);
    if (type == FileSystemEntityType.notFound) return _status(req, 404);
    final depth = req.headers.value('depth') ?? '1';
    final sb = StringBuffer('<?xml version="1.0" encoding="utf-8"?><D:multistatus xmlns:D="DAV:">');
    void entry(FileSystemEntity e) {
      FileStat st;
      try {
        st = e.statSync();
      } catch (_) {
        return;
      }
      final dir = st.type == FileSystemEntityType.directory;
      final name = p.basename(e.path);
      sb.write('<D:response><D:href>${_x(_href(e.path, dir))}</D:href><D:propstat><D:prop>');
      sb.write('<D:displayname>${_x(e.path == rootPath ? cfg.name : name)}</D:displayname>');
      sb.write('<D:resourcetype>${dir ? '<D:collection/>' : ''}</D:resourcetype>');
      sb.write('<D:getlastmodified>${HttpDate.format(st.modified.toUtc())}</D:getlastmodified>');
      if (!dir) {
        sb.write('<D:getcontentlength>${st.size}</D:getcontentlength>');
        sb.write('<D:getcontenttype>${_x(lookupMimeType(name) ?? 'application/octet-stream')}</D:getcontenttype>');
      }
      sb.write('<D:supportedlock><D:lockentry><D:lockscope><D:exclusive/></D:lockscope><D:locktype><D:write/></D:locktype></D:lockentry></D:supportedlock>');
      sb.write('</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>');
    }

    entry(type == FileSystemEntityType.directory ? Directory(target) : File(target));
    if (type == FileSystemEntityType.directory && depth != '0') {
      try {
        final list = Directory(target).listSync(followLinks: false).where((e) => !p.basename(e.path).startsWith('.')).toList()
          ..sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
        list.forEach(entry);
      } catch (_) {}
    }
    sb.write('</D:multistatus>');
    return _status(req, 207, sb.toString(), 'application/xml; charset=utf-8');
  }

  Future<void> _get(HttpRequest req, String target, {required bool head}) async {
    final res = req.response;
    if (FileSystemEntity.isDirectorySync(target)) {
      return _status(req, 200, 'PocketServer WebDAV - mount this address as a network drive.');
    }
    final f = File(target);
    if (!f.existsSync()) return _status(req, 404);
    final len = await f.length();
    res.headers.set('Accept-Ranges', 'bytes');
    res.headers.contentType = ContentType.parse(lookupMimeType(target) ?? 'application/octet-stream');
    res.headers.set('Last-Modified', HttpDate.format(f.lastModifiedSync().toUtc()));
    var start = 0, end = len - 1;
    final rh = req.headers.value('range');
    if (rh != null) {
      final m = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rh);
      if (m != null) {
        final a = m.group(1)!, b = m.group(2)!;
        if (a.isEmpty && b.isNotEmpty) {
          start = (len - int.parse(b)).clamp(0, len);
        } else if (a.isNotEmpty) {
          start = int.parse(a);
          if (b.isNotEmpty) end = int.parse(b).clamp(0, len - 1);
        }
        if (start > end || start >= len) {
          res.headers.set('Content-Range', 'bytes */$len');
          return _status(req, 416);
        }
        res.statusCode = 206;
        res.headers.set('Content-Range', 'bytes $start-$end/$len');
      }
    }
    final count = len == 0 ? 0 : end - start + 1;
    res.headers.set('Content-Length', '$count');
    if (head || count == 0) {
      await res.close();
      return;
    }
    Stats.i.addOut(count, cfg.id);
    if (start == 0) Stats.i.event(cfg.id, 'download', p.basename(target));
    try {
      await res.addStream(f.openRead(start, end + 1));
    } catch (_) {}
    try {
      await res.close();
    } catch (_) {}
  }

  Future<void> _put(HttpRequest req, String target) async {
    if (FileSystemEntity.isDirectorySync(target)) return _status(req, 405);
    if (!Directory(p.dirname(target)).existsSync()) {
      await req.drain<void>();
      return _status(req, 409);
    }
    final existed = File(target).existsSync();
    final tmp = File('$target.part-${DateTime.now().microsecondsSinceEpoch}');
    var got = 0;
    try {
      final sink = tmp.openWrite();
      await sink.addStream(req.map((c) {
        got += c.length;
        return c;
      }));
      await sink.close();
      if (existed) await File(target).delete();
      await tmp.rename(target);
    } catch (_) {
      try {
        await tmp.delete();
      } catch (_) {}
      return _status(req, 500);
    }
    Stats.i.addIn(got, cfg.id);
    Stats.i.event(cfg.id, 'upload', p.basename(target));
    return _status(req, existed ? 204 : 201);
  }

  Future<void> _delete(HttpRequest req, String target) async {
    if (p.normalize(target) == p.normalize(rootPath)) return _status(req, 403);
    final t = FileSystemEntity.typeSync(target);
    if (t == FileSystemEntityType.notFound) return _status(req, 404);
    try {
      if (t == FileSystemEntityType.directory) {
        await Directory(target).delete(recursive: true);
      } else {
        await File(target).delete();
      }
    } catch (_) {
      return _status(req, 500);
    }
    return _status(req, 204);
  }

  Future<void> _moveCopy(HttpRequest req, String src, {required bool move}) async {
    final dh = req.headers.value('destination');
    if (dh == null) return _status(req, 400);
    final dst = _map(Uri.parse(dh).path);
    if (dst == null) return _status(req, 403);
    final st = FileSystemEntity.typeSync(src);
    if (st == FileSystemEntityType.notFound) return _status(req, 404);
    if (p.normalize(src) == p.normalize(rootPath) || p.normalize(dst) == p.normalize(rootPath)) return _status(req, 403);
    if (p.isWithin(src, dst)) return _status(req, 403);
    if (!Directory(p.dirname(dst)).existsSync()) return _status(req, 409);
    final over = (req.headers.value('overwrite') ?? 'T').toUpperCase() != 'F';
    final exists = FileSystemEntity.typeSync(dst) != FileSystemEntityType.notFound;
    if (exists && !over) return _status(req, 412);
    try {
      if (exists) {
        if (FileSystemEntity.isDirectorySync(dst)) {
          await Directory(dst).delete(recursive: true);
        } else {
          await File(dst).delete();
        }
      }
      if (move) {
        try {
          if (st == FileSystemEntityType.directory) {
            await Directory(src).rename(dst);
          } else {
            await File(src).rename(dst);
          }
        } on FileSystemException {
          await _copy(src, dst);
          await (st == FileSystemEntityType.directory ? Directory(src).delete(recursive: true) : File(src).delete());
        }
      } else {
        await _copy(src, dst);
      }
    } catch (_) {
      return _status(req, 500);
    }
    return _status(req, exists ? 204 : 201);
  }

  Future<void> _copy(String src, String dst) async {
    if (FileSystemEntity.isDirectorySync(src)) {
      await Directory(dst).create();
      await for (final e in Directory(src).list(followLinks: false)) {
        await _copy(e.path, p.join(dst, p.basename(e.path)));
      }
    } else {
      await File(src).copy(dst);
    }
  }
}
