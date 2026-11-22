import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import 'share_store.dart';
import 'login_guard.dart';
import 'stats.dart';
import 'web_ui.dart';

/// Dart port of the original Flask "PocketServer" server (files.py), without
/// the converter / compressor.
class WebServer {
  WebServer(this.store, this.port, {this.id = 'web'});

  final String id;
  final ShareStore store;
  final int port;
  HttpServer? _server;
  int _tmpCounter = 0;

  bool get running => _server != null;

  Future<void> start() async {
    final s = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
    s.autoCompress = false;
    _server = s;
    s.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }

  // ── plumbing ──────────────────────────────────────────────────────────────
  String? _sid(HttpRequest req) {
    for (final c in req.cookies) {
      if (c.name == 'sid') return c.value;
    }
    return null;
  }

  Future<String> _body(HttpRequest req) => utf8.decoder.bind(req).join();

  Future<dynamic> _jsonBody(HttpRequest req) async {
    final s = await _body(req);
    if (s.trim().isEmpty) return <String, dynamic>{};
    return jsonDecode(s);
  }

  Future<Map<String, dynamic>> _mapBody(HttpRequest req) async {
    final v = await _jsonBody(req);
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  Future<void> _json(HttpResponse res, Object? data, [int status = 200]) async {
    res.statusCode = status;
    res.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    res.headers.set('Cache-Control', 'no-store');
    res.write(jsonEncode(data));
    await res.close();
  }

  Future<void> _err(HttpResponse res, String msg, [int status = 400]) =>
      _json(res, {'error': msg}, status);

  Future<void> _text(HttpResponse res, String msg, int status) async {
    res.statusCode = status;
    res.headers.contentType = ContentType.text;
    res.write(msg);
    await res.close();
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final path = req.uri.path;
      final m = req.method;
      final user = store.sessionUser(_sid(req));
      Stats.i.requests++;

      if (m == 'GET' && path == '/') {
        res.headers.contentType = ContentType.html;
        res.headers.set('Cache-Control', 'no-cache');
        res.write(kWebUiHtml);
        await res.close();
        return;
      }
      if (m == 'GET' && path.startsWith('/file/')) {
        return await _serve(req, res, user, _tail(req, 1), attachment: false);
      }
      if (m == 'GET' && path.startsWith('/download/')) {
        return await _serve(req, res, user, _tail(req, 1), attachment: true);
      }
      if (m == 'GET' && path.startsWith('/share/')) {
        return await _shareDownload(req, res, _tail(req, 1));
      }

      switch ('$m $path') {
        case 'GET /api/me':
          return await _me(res, user);
        case 'GET /api/users':
          return await _json(res, {'users': store.loadMap(store.usersFile).keys.toList()});
        case 'POST /api/register':
          return await _register(req, res);
        case 'POST /api/login':
          return await _login(req, res);
        case 'POST /api/logout':
          store.destroySession(_sid(req));
          res.headers.add('Set-Cookie', 'sid=; Path=/; Max-Age=0; HttpOnly');
          return await _json(res, {'status': 'ok'});
        case 'POST /api/avatar':
          return await _avatar(req, res, user);
        case 'POST /api/change_password':
          return await _changePassword(req, res, user);
        case 'POST /api/set_default_privacy':
          return await _setDefaultPrivacy(req, res, user);
        case 'POST /api/set_perm':
          return await _setPerm(req, res, user);
        case 'GET /api/file_perms':
          return await _json(res, _permEntry(req.uri.queryParameters['path'] ?? ''));
        case 'GET /api/get_perm':
          return await _getPerm(req, res);
        case 'GET /api/files':
          return await _files(req, res, user);
        case 'POST /api/upload':
          return await _upload(req, res, user);
        case 'POST /api/bulk':
          return await _bulk(req, res, user);
        case 'POST /api/rename':
          return await _rename(req, res, user);
        case 'POST /api/download_bulk':
          return await _downloadBulk(req, res, user);
        case 'POST /api/folder':
          return await _folder(req, res, user);
        case 'GET /api/clipboards':
          return await _json(res, user == null ? [] : _userList(store.clipFile, user));
        case 'POST /api/clipboards':
          return await _saveUserList(req, res, user, store.clipFile);
        case 'POST /api/clipboard_to_file':
          return await _clipboardToFile(req, res, user);
        case 'POST /api/clipboard_perm':
          return await _clipboardPerm(req, res, user);
        case 'GET /api/links':
          return await _json(res, user == null ? [] : _userList(store.linksFile, user));
        case 'POST /api/links':
          return await _saveUserList(req, res, user, store.linksFile);
        case 'GET /api/notes':
          return await _getNotes(req, res);
        case 'POST /api/notes':
          return await _saveNote(req, res, user);
        case 'POST /api/notes/delete':
          return await _deleteNote(req, res, user);
        case 'POST /api/star':
          return await _toggleStar(req, res, user);
        case 'GET /api/stars':
          return await _json(res, user == null ? [] : _userList(store.starsFile, user));
        case 'POST /api/duplicate':
          return await _duplicate(req, res, user);
        case 'GET /api/activity':
          return await _activity(res, user);
        case 'POST /api/bulk_access':
          return await _bulkAccess(req, res, user);
        case 'GET /api/storage_stats':
          return await _storageStats(res, user);
        case 'POST /api/share_link':
          return await _createShareLink(req, res, user);
        case 'GET /api/file_content':
          return await _fileContent(req, res, user);
        case 'POST /api/file_save':
          return await _fileSave(req, res, user);
        case 'GET /api/file_info':
          return await _fileInfoApi(req, res, user);
        case 'POST /api/delete_account':
          return await _deleteAccount(req, res, user);
      }
      await _text(res, 'Not found', 404);
    } catch (e) {
      try {
        await _err(res, e.toString(), 500);
      } catch (_) {}
    }
  }

  /// Decoded path after the first [skip] segments.
  String _tail(HttpRequest req, int skip) =>
      req.uri.pathSegments.skip(skip).join('/');

  Map<String, dynamic> _permEntry(String path) {
    final raw = store.loadMap(store.permsFile)[path];
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  List<dynamic> _userList(File f, String user) {
    final all = store.loadMap(f);
    final v = all[user];
    return v is List ? v : <dynamic>[];
  }

  // ── auth ──────────────────────────────────────────────────────────────────
  Future<void> _me(HttpResponse res, String? u) async {
    if (u == null) return _json(res, {});
    return _json(res, {
      'username': u,
      'avatar': store.userAvatar(u),
      'default_privacy': store.defaultPrivacy(u),
      'usage': store.usage(),
    });
  }

  void _setSessionCookie(HttpResponse res, String sid) {
    res.headers.add('Set-Cookie',
        'sid=$sid; Path=/; Max-Age=31536000; HttpOnly; SameSite=Lax');
  }

  Future<void> _register(HttpRequest req, HttpResponse res) async {
    final d = await _mapBody(req);
    final u = ((d['username'] as String?) ?? '').trim();
    final pw = (d['password'] as String?) ?? '';
    if (u.isEmpty || pw.isEmpty) return _err(res, 'Username and password required');
    if (u.length < 2) return _err(res, 'Username must be 2+ characters');
    if (pw.length < 4) return _err(res, 'Password must be 4+ characters');
    if (u.contains('/') || u.contains('\\') || u.startsWith('.')) {
      return _err(res, 'Invalid username');
    }
    final users = store.loadMap(store.usersFile);
    if (users.containsKey(u)) return _err(res, 'Username already taken');
    users[u] = {
      'password': sha256Hex(pw),
      'created': DateTime.now().millisecondsSinceEpoch / 1000,
      'default_privacy': 'public',
    };
    store.saveJson(store.usersFile, users);
    _setSessionCookie(res, store.createSession(u));
    return _json(res, {'status': 'ok', 'avatar': null});
  }

  Future<void> _login(HttpRequest req, HttpResponse res) async {
    final ip = req.connectionInfo?.remoteAddress.address ?? '';
    if (LoginGuard.i.isLocked(ip)) return _err(res, 'Too many failed logins. Try again in a few minutes.', 429);
    final d = await _mapBody(req);
    final u = ((d['username'] as String?) ?? '').trim();
    final pw = (d['password'] as String?) ?? '';
    final users = store.loadMap(store.usersFile);
    final rec = users[u];
    if (rec is! Map || rec['password'] != sha256Hex(pw)) {
      Stats.i.event(id, 'failed', u);
      LoginGuard.i.fail(ip);
      return _err(res, 'Invalid username or password', 401);
    }
    LoginGuard.i.ok(ip);
    _setSessionCookie(res, store.createSession(u));
    Stats.i.event(id, 'login', u);
    return _json(res, {'status': 'ok', 'username': u, 'avatar': store.userAvatar(u)});
  }

  Future<void> _avatar(HttpRequest req, HttpResponse res, String? u) async {
    if (u == null) return _err(res, 'Not logged in', 401);
    final parts = await _readMultipart(req);
    final f = parts.files.where((e) => e.field == 'avatar').toList();
    if (f.isEmpty) return _err(res, 'No file');
    try {
      final bytes = await f.first.tmp.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw const FormatException('not an image');
      final small = decoded.width > 200 ? img.copyResize(decoded, width: 200) : decoded;
      final jpg = img.encodeJpg(small, quality: 85);
      for (final ext in const ['png', 'jpg']) {
        final old = File(p.join(store.avatarsDir.path, '$u.$ext'));
        if (old.existsSync()) old.deleteSync();
      }
      File(p.join(store.avatarsDir.path, '$u.jpg')).writeAsBytesSync(jpg);
      store.invalidateAvatar(u);
    } catch (e) {
      return _err(res, 'Could not read image: $e');
    } finally {
      await parts.cleanup();
    }
    return _json(res, {'status': 'ok', 'avatar': store.userAvatar(u)});
  }

  Future<void> _setDefaultPrivacy(HttpRequest req, HttpResponse res, String? u) async {
    if (u == null) return _err(res, 'Not logged in', 401);
    final d = await _mapBody(req);
    final users = store.loadMap(store.usersFile);
    final rec = users[u];
    if (rec is Map) {
      final mm = Map<String, dynamic>.from(rec);
      mm['default_privacy'] = (d['privacy'] as String?) ?? 'public';
      users[u] = mm;
      store.saveJson(store.usersFile, users);
    }
    return _json(res, {'status': 'ok'});
  }

  Future<void> _changePassword(HttpRequest req, HttpResponse res, String? u) async {
    if (u == null) return _err(res, 'Not logged in', 401);
    final d = await _mapBody(req);
    final oldPw = (d['old_password'] as String?) ?? '';
    final newPw = (d['new_password'] as String?) ?? '';
    if (oldPw.isEmpty || newPw.isEmpty) return _err(res, 'Both fields required');
    if (newPw.length < 4) return _err(res, 'Password too short (min 4)');
    final users = store.loadMap(store.usersFile);
    final rec = users[u];
    if (rec is! Map || rec['password'] != sha256Hex(oldPw)) {
      return _err(res, 'Current password incorrect', 401);
    }
    final mm = Map<String, dynamic>.from(rec);
    mm['password'] = sha256Hex(newPw);
    users[u] = mm;
    store.saveJson(store.usersFile, users);
    return _json(res, {'status': 'ok'});
  }

  // ── permissions ──────────────────────────────────────────────────────────
  Future<void> _setPerm(HttpRequest req, HttpResponse res, String? u) async {
    if (u == null) return _err(res, 'Not logged in', 401);
    final d = await _mapBody(req);
    final path = (d['path'] as String?) ?? '';
    final perms = store.loadMap(store.permsFile);
    final existing = perms[path] is Map ? Map<String, dynamic>.from(perms[path] as Map) : <String, dynamic>{};
    final owner = existing['owner'];
    if (owner != null && owner != u) return _err(res, 'Not the owner', 403);
    perms[path] = {
      'owner': owner ?? u,
      'visibility': (d['visibility'] as String?) ?? 'public',
      'allowed_users': (d['allowed_users'] as List?) ?? [],
    };
    store.saveJson(store.permsFile, perms);
    return _json(res, {'status': 'ok'});
  }

  Future<void> _getPerm(HttpRequest req, HttpResponse res) {
    final pm = _permEntry(req.uri.queryParameters['path'] ?? '');
    return _json(res, {
      'visibility': pm['visibility'] ?? 'public',
      'allowed_users': pm['allowed_users'] ?? [],
      'owner': pm['owner'],
    });
  }

  Future<void> _bulkAccess(HttpRequest req, HttpResponse res, String? u) async {
    if (u == null) return _err(res, 'Not logged in', 401);
    final d = await _mapBody(req);
    final items = ((d['items'] as List?) ?? []).cast<String>();
    final vis = (d['visibility'] as String?) ?? 'public';
    final allowed = (d['allowed_users'] as List?) ?? [];
    final perms = store.loadMap(store.permsFile);
    for (final path in items) {
      final ex = perms[path];
      final owner = ex is Map ? ex['owner'] : null;
      if (owner == null || owner == u) {
        perms[path] = {'owner': u, 'visibility': vis, 'allowed_users': allowed};
      }
    }
    store.saveJson(store.permsFile, perms);
    return _json(res, {'status': 'ok', 'updated': items.length});
  }

  // ── files ─────────────────────────────────────────────────────────────────
  Future<void> _files(HttpRequest req, HttpResponse res, String? user) {
    final q = req.uri.queryParameters;
    final items = store.contentData(
        q['path'] ?? '', q['sort'] ?? 'date', q['search'] ?? '', user);
    return _json(res, {'items': items, 'usage': store.usage()});
  }

  Future<void> _folder(HttpRequest req, HttpResponse res, String? u) async {
    if (u == null) return _err(res, 'Not logged in', 401);
    final d = await _mapBody(req);
    final base = store.safeJoin(store.rootPath, (d['path'] as String?) ?? '');
    final nm = ((d['name'] as String?) ?? '').trim();
    if (base == null || nm.isEmpty || nm.contains('/') || nm.contains('\\') || nm.startsWith('.')) {
      return _err(res, 'Invalid folder name');
    }
    final full = p.join(base, nm);
    Directory(full).createSync(recursive: true);
    final rel = store.relOf(full);
    final perms = store.loadMap(store.permsFile);
    perms.putIfAbsent(rel, () => {'owner': u, 'visibility': store.defaultPrivacy(u), 'allowed_users': []});
    store.saveJson(store.permsFile, perms);
    return _json(res, {'status': 'ok'});
  }

  Future<void> _upload(HttpRequest req, HttpResponse res, String? user) async {
    if (user == null) return _err(res, 'Not logged in', 401);
    final parts = await _readMultipart(req);
    try {
      final current = parts.fields['path'] ?? '';
      final target = store.safeJoin(store.rootPath, current);
      if (target == null) return _text(res, 'Invalid path', 400);
      final paths = parts.fieldLists['paths[]'] ?? const <String>[];
      final defPriv = store.defaultPrivacy(user);
      final meta = store.loadMap(store.metaFile);
      final perms = store.loadMap(store.permsFile);
      final files = parts.files.where((f) => f.field == 'files[]').toList();
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        final rel = i < paths.length && paths[i].isNotEmpty ? paths[i] : f.filename;
        final full = store.safeJoin(target, rel);
        if (full == null || full == target || p.basename(full).startsWith('.')) continue;
        Directory(p.dirname(full)).createSync(recursive: true);
        try {
          Stats.i.addIn(await f.tmp.length(), id);
          Stats.i.event(id, 'upload', rel);
        } catch (_) {}
        if (kTextExts.contains(p.extension(rel).toLowerCase())) {
          final raw = await f.tmp.readAsBytes();
          await File(full).writeAsBytes(raw.isEmpty ? raw : store.asCleanUtf8(raw));
        } else {
          try {
            await f.tmp.rename(full);
          } on FileSystemException {
            await f.tmp.copy(full);
          }
        }
        final rootRel = store.relOf(full);
        meta[rootRel] = user;
        perms.putIfAbsent(rootRel, () => {'owner': user, 'visibility': defPriv, 'allowed_users': []});
      }
      store.saveJson(store.metaFile, meta);
      store.saveJson(store.permsFile, perms);
    } finally {
      await parts.cleanup();
    }
    return _json(res, {'status': 'ok'});
  }

  Future<void> _bulk(HttpRequest req, HttpResponse res, String? acting) async {
    if (acting == null) return _err(res, 'Not logged in', 401);
    final d = await _mapBody(req);
    final action = d['action'] as String?;
    final items = ((d['items'] as List?) ?? []).cast<String>();
    final base = store.safeJoin(store.rootPath, (d['path'] as String?) ?? '');
    final extra = d['extra'] as String?;
    if (base == null) return _err(res, 'Invalid path');

    if (action == 'zip' && extra != null && extra.isNotEmpty) {
      final zn = extra.endsWith('.zip') ? extra : '$extra.zip';
      final zp = store.safeJoin(base, zn);
      if (zp == null) return _err(res, 'Invalid archive name');
      final entries = <MapEntry<String, File>>[];
      for (final item in items) {
        final full = store.safeJoin(base, item);
        if (full == null) continue;
        if (!store.canAccess(store.relOf(full), acting)) continue;
        if (FileSystemEntity.isDirectorySync(full)) {
          for (final e in Directory(full).listSync(recursive: true, followLinks: false)) {
            if (e is File) entries.add(MapEntry(p.relative(e.path, from: base).replaceAll('\\', '/'), e));
          }
        } else if (FileSystemEntity.isFileSync(full)) {
          entries.add(MapEntry(item, File(full)));
        }
      }
      try {
        final enc = ZipFileEncoder();
        enc.create(zp);
        for (final e in entries) {
          await enc.addFile(e.value, e.key);
        }
        await enc.close();
        final rel = store.relOf(zp);
        final perms = store.loadMap(store.permsFile);
        perms.putIfAbsent(rel, () => {'owner': acting, 'visibility': store.defaultPrivacy(acting), 'allowed_users': []});
        store.saveJson(store.permsFile, perms);
      } catch (e) {
        // ignore: avoid_print
        print('zip error: $e');
      }
      return _json(res, {'status': 'ok'});
    }

    for (final item in items) {
      final full = store.safeJoin(base, item);
      if (full == null || full == store.rootPath) continue;
      try {
        final rel = store.relOf(full);
        final perms = store.loadMap(store.permsFile);
        final pe = perms[rel];
        final owner = pe is Map ? pe['owner'] : null;
        if (owner != null && owner != acting) continue; // not the owner
        final isDir = FileSystemEntity.isDirectorySync(full);
        switch (action) {
          case 'delete':
            if (isDir) {
              await Directory(full).delete(recursive: true);
            } else if (FileSystemEntity.isFileSync(full)) {
              await File(full).delete();
            }
            perms.removeWhere((k, _) => k == rel || k.startsWith('$rel/'));
            store.saveJson(store.permsFile, perms);
          case 'move':
            if (extra == null) break;
            final dest = store.safeJoin(store.rootPath, extra);
            if (dest == null) break;
            Directory(dest).createSync(recursive: true);
            final target = p.join(dest, p.basename(full));
            try {
              await (isDir ? Directory(full).rename(target) : File(full).rename(target));
            } on FileSystemException {
              if (isDir) {
                await _copyDir(Directory(full), Directory(target));
                await Directory(full).delete(recursive: true);
              } else {
                await File(full).copy(target);
                await File(full).delete();
              }
            }
            final newRel = store.relOf(target);
            final moved = <String, dynamic>{};
            perms.forEach((k, v) {
              if (k == rel || k.startsWith('$rel/')) moved[newRel + k.substring(rel.length)] = v;
            });
            perms.removeWhere((k, _) => k == rel || k.startsWith('$rel/'));
            perms.addAll(moved);
            store.saveJson(store.permsFile, perms);
          case 'copy':
            if (extra == null) break;
            final dest = store.safeJoin(store.rootPath, extra);
            if (dest == null) break;
            Directory(dest).createSync(recursive: true);
            final target = p.join(dest, p.basename(full));
            if (isDir) {
              await _copyDir(Directory(full), Directory(target));
            } else {
              await File(full).copy(target);
            }
            perms[store.relOf(target)] = {
              'owner': acting,
              'visibility': store.defaultPrivacy(acting),
              'allowed_users': [],
            };
            store.saveJson(store.permsFile, perms);
          case 'unzip':
            if (item.toLowerCase().endsWith('.zip')) {
              await extractFileToDisk(full, base);
            }
        }
      } catch (e) {
        // ignore: avoid_print
        print('bulk error: $e');
      }
    }
    return _json(res, {'status': 'ok'});
  }

  Future<void> _copyDir(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final e in from.list(followLinks: false)) {
      final name = p.basename(e.path);
      if (e is Directory) {
        await _copyDir(e, Directory(p.join(to.path, name)));
      } else if (e is File) {
        await e.copy(p.join(to.path, name));
      }
    }
  }

  Future<void> _rename(HttpRequest req, HttpResponse res, String? u) async {
    if (u == null) return _err(res, 'Not logged in', 401);
    final d = await _mapBody(req);
    final path = (d['path'] as String?) ?? '';
    final newName = ((d['new_name'] as String?) ?? '').trim();
    if (newName.isEmpty || newName.contains('/') || newName.contains('\\') || newName.startsWith('.')) {
      return _err(res, 'Invalid name');
    }
    final perms = store.loadMap(store.permsFile);
    final pe = perms[path];
    final owner = pe is Map ? pe['owner'] : null;
    if (owner != null && owner != u) return _err(res, 'Not the owner — cannot rename', 403);
    final full = store.safeJoin(store.rootPath, path);
    if (full == null || full == store.rootPath || FileSystemEntity.typeSync(full) == FileSystemEntityType.notFound) {
      return _err(res, 'Not found', 404);
    }
    final newFull = p.join(p.dirname(full), newName);
    if (FileSystemEntity.typeSync(newFull) != FileSystemEntityType.notFound) {
      return _err(res, 'A file with that name already exists');
    }
    final isDir = FileSystemEntity.isDirectorySync(full);
    await (isDir ? Directory(full).rename(newFull) : File(full).rename(newFull));
    final newRel = store.relOf(newFull);
    final moved = <String, dynamic>{};
    perms.forEach((k, v) {
      if (k == path || k.startsWith('$path/')) moved[newRel + k.substring(path.length)] = v;
    });
    perms.removeWhere((k, _) => k == path || k.startsWith('$path/'));
    perms.addAll(moved);
    store.saveJson(store.permsFile, perms);
    return _json(res, {'status': 'ok'});
  }

  Future<void> _duplicate(HttpRequest req, HttpResponse res, String? u) async {
    if (u == null) return _err(res, 'Not logged in', 401);
    final d = await _mapBody(req);
    final relSrc = (d['path'] as String?) ?? '';
    final src = store.safeJoin(store.rootPath, relSrc);
    if (src == null || !FileSystemEntity.isFileSync(src)) return _err(res, 'File not found', 404);
    if (!store.canAccess(relSrc, u)) return _err(res, 'Access denied', 403);
    final base = p.withoutExtension(src);
    final ext = p.extension(src);
    var dst = '${base}_copy$ext';
    var i = 2;
    while (FileSystemEntity.typeSync(dst) != FileSystemEntityType.notFound) {
      dst = '${base}_copy$i$ext';
      i++;
    }
    await File(src).copy(dst);
    final perms = store.loadMap(store.permsFile);
    final relDst = store.relOf(dst);
    final old = perms[relSrc];
    final entry = old is Map ? Map<String, dynamic>.from(old) : <String, dynamic>{'visibility': store.defaultPrivacy(u), 'allowed_users': []};
    entry['owner'] = u;
    perms[relDst] = entry;
    store.saveJson(store.permsFile, perms);
    return _json(res, {'status': 'ok', 'new_name': p.basename(dst)});
  }

  // ── serving / downloading ────────────────────────────────────────────────
  Future<void> _serve(HttpRequest req, HttpResponse res, String? viewer, String filename,
      {required bool attachment}) async {
    if (!store.canAccess(filename, viewer)) return _text(res, 'Access denied', 403);
    final full = store.safeJoin(store.rootPath, filename);
    if (full == null || p.basename(full).startsWith('.') || !FileSystemEntity.isFileSync(full)) {
      return _text(res, 'Not found', 404);
    }
    final ext = p.extension(full).toLowerCase();
    final name = p.basename(full);
    if (kTextExts.contains(ext)) {
      final raw = await File(full).readAsBytes();
      var data = store.asCleanUtf8(raw);
      if (attachment) {
        data = [0xEF, 0xBB, 0xBF, ...data]; // BOM so every editor opens it as UTF-8
        res.headers.contentType = ContentType.binary;
        res.headers.set('Content-Disposition', _disposition(name));
      } else {
        res.headers.set('Content-Type', 'text/plain; charset=utf-8');
      }
      res.headers.set('Content-Length', data.length.toString());
      res.add(data);
      await res.close();
      return;
    }
    await _sendFile(req, res, File(full), name, attachment);
  }

  String _disposition(String name) {
    final ascii = name.replaceAll(RegExp(r'[^\x20-\x7E]'), '_').replaceAll('"', '_');
    return "attachment; filename=\"$ascii\"; filename*=UTF-8''${Uri.encodeComponent(name)}";
  }

  Future<void> _sendFile(HttpRequest req, HttpResponse res, File f, String name, bool attachment) async {
    final len = await f.length();
    final mime = lookupMimeType(name) ?? 'application/octet-stream';
    res.headers.set('Content-Type', mime);
    res.headers.set('Accept-Ranges', 'bytes');
    if (attachment) res.headers.set('Content-Disposition', _disposition(name));
    var start = 0;
    var end = len - 1;
    final range = req.headers.value('range');
    if (range != null) {
      final m = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range.trim());
      if (m != null && (m.group(1)!.isNotEmpty || m.group(2)!.isNotEmpty)) {
        if (m.group(1)!.isEmpty) {
          final n = int.parse(m.group(2)!);
          start = max(0, len - n);
        } else {
          start = int.parse(m.group(1)!);
          if (m.group(2)!.isNotEmpty) end = min(end, int.parse(m.group(2)!));
        }
        if (start >= len || start > end) {
          res.statusCode = 416;
          res.headers.set('Content-Range', 'bytes */$len');
          await res.close();
          return;
        }
        res.statusCode = 206;
        res.headers.set('Content-Range', 'bytes $start-$end/$len');
      }
    }
    final count = len == 0 ? 0 : end - start + 1;
    res.headers.set('Content-Length', count.toString());
    if (count == 0) {
      await res.close();
      return;
    }
    Stats.i.addOut(count, id);
    if (start == 0) Stats.i.event(id, 'download', name);
    try {
      await res.addStream(f.openRead(start, end + 1));
    } catch (_) {}
    try {
      await res.close();
    } catch (_) {}
  }

  Future<void> _downloadBulk(HttpRequest req, HttpResponse res, String? viewer) async {
    final q = Uri(query: await _body(req)).queryParametersAll;
    final path = (q['path'] ?? const ['']).first;
    final items = q['items'] ?? const <String>[];
    final base = store.safeJoin(store.rootPath, path);
    if (base == null) return _text(res, 'Invalid path', 400);
    if (items.length == 1) {
      final full = store.safeJoin(base, items.first);
      if (full != null && FileSystemEntity.isFileSync(full)) {
        if (!store.canAccess(store.relOf(full), viewer)) return _text(res, 'Access denied', 403);
        return _serve(req, res, viewer, store.relOf(full), attachment: true);
      }
    }
    final entries = <MapEntry<String, File>>[];
    for (final item in items) {
      final full = store.safeJoin(base, item);
      if (full == null) continue;
      if (!store.canAccess(store.relOf(full), viewer)) continue;
      if (FileSystemEntity.isDirectorySync(full)) {
        for (final e in Directory(full).listSync(recursive: true, followLinks: false)) {
          if (e is File && !p.basename(e.path).startsWith('.')) {
            entries.add(MapEntry(p.relative(e.path, from: p.dirname(full)).replaceAll('\\', '/'), e));
          }
        }
      } else if (FileSystemEntity.isFileSync(full)) {
        entries.add(MapEntry(item, File(full)));
      }
    }
    final tmp = File(p.join(store.tmpDir.path, 'dl_${DateTime.now().microsecondsSinceEpoch}_${_tmpCounter++}.zip'));
    try {
      final enc = ZipFileEncoder();
      enc.create(tmp.path);
      for (final e in entries) {
        await enc.addFile(e.value, e.key);
      }
      await enc.close();
      res.headers.set('Content-Type', 'application/zip');
      res.headers.set('Content-Disposition', _disposition('archive.zip'));
      res.headers.set('Content-Length', (await tmp.length()).toString());
      await res.addStream(tmp.openRead());
      await res.close();
    } finally {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
    }
  }

  // ── clipboards / links / stars ───────────────────────────────────────────
  Future<void> _saveUserList(HttpRequest req, HttpResponse res, String? u, File f) async {
    if (u == null) return _err(res, 'Not logged in', 401);
    final v = await _jsonBody(req);
    final all = store.loadMap(f);
    all[u] = v is List ? v : <dynamic>[];
    store.saveJson(f, all);
    return _json(res, {'status': 'ok'});
  }

  Future<void> _clipboardToFile(HttpRequest req, HttpResponse res, String? u) async {
    if (u == null) return _err(res, 'Not logged in', 401);
    final d = await _mapBody(req);
    final text = (d['text'] as String?) ?? '';
    var filename = p.basename(((d['filename'] as String?) ?? 'snippet.txt').replaceAll('\\', '/'));
    if (filename.isEmpty || filename.startsWith('.')) filename = 'snippet.txt';
    final td = store.safeJoin(store.rootPath, (d['path'] as String?) ?? '');
    if (td == null) return _err(res, 'Bad path');
    Directory(td).createSync(recursive: true);
    final full = p.join(td, filename);
    await File(full).writeAsString(text);
    final perms = store.loadMap(store.permsFile);
    perms[store.relOf(full)] = {'owner': u, 'visibility': store.defaultPrivacy(u), 'allowed_users': []};
    store.saveJson(store.permsFile, perms);
    return _json(res, {'status': 'ok'});
  }

  Future<void> _clipboardPerm(HttpRequest req, HttpResponse res, String? u) async {
    if (u == null) return _err(res, 'Not logged in', 401);
    final d = await _mapBody(req);
    final idx = d['idx'];
    final all = store.loadMap(store.clipFile);
    final clips = _userList(store.clipFile, u);
    if (idx is int && idx >= 0 && idx < clips.length && clips[idx] is Map) {
      final c = Map<String, dynamic>.from(clips[idx] as Map);
      c['visibility'] = (d['visibility'] as String?) ?? 'private';
      c['allowed_users'] = d['allowed_users'] ?? [];
      clips[idx] = c;
      all[u] = clips;
      store.saveJson(store.clipFile, all);
    }
    return _json(res, {'status': 'ok'});
  }

  Future<void> _getNotes(HttpRequest req, HttpResponse res) {
    final path = req.uri.queryParameters['path'] ?? '';
    final v = store.loadMap(store.notesFile)[path];
    return _json(res, v is List ? v : <dynamic>[]);
  }

  Future<void> _saveNote(HttpRequest req, HttpResponse res, String? u) async {
    if (u == null) return _err(res, 'Not logged in', 401);
    final d = await _mapBody(req);
    final path = (d['path'] as String?) ?? '';
    final text = ((d['text'] as String?) ?? '').trim();
    if (text.isEmpty) return _err(res, 'Empty note');
    final notes = store.loadMap(store.notesFile);
    final lst = notes[path] is List ? List<dynamic>.from(notes[path] as List) : <dynamic>[];
    lst.add({'user': u, 'text': text, 'ts': DateTime.now().millisecondsSinceEpoch / 1000});
    notes[path] = lst;
    store.saveJson(store.notesFile, notes);
    return _json(res, {'status': 'ok'});
  }

  Future<void> _deleteNote(HttpRequest req, HttpResponse res, String? u) async {
    if (u == null) return _err(res, 'Not logged in', 401);
    final d = await _mapBody(req);
    final path = (d['path'] as String?) ?? '';
    final idx = d['idx'];
    final notes = store.loadMap(store.notesFile);
    final lst = notes[path] is List ? List<dynamic>.from(notes[path] as List) : <dynamic>[];
    if (idx is int && idx >= 0 && idx < lst.length && lst[idx] is Map && (lst[idx] as Map)['user'] == u) {
      lst.removeAt(idx);
      notes[path] = lst;
      store.saveJson(store.notesFile, notes);
    }
    return _json(res, {'status': 'ok'});
  }

  Future<void> _toggleStar(HttpRequest req, HttpResponse res, String? u) async {
    if (u == null) return _err(res, 'Not logged in', 401);
    final d = await _mapBody(req);
    final path = (d['path'] as String?) ?? '';
    final stars = store.loadMap(store.starsFile);
    final mine = stars[u] is List ? List<dynamic>.from(stars[u] as List) : <dynamic>[];
    if (!mine.remove(path)) mine.add(path);
    stars[u] = mine;
    store.saveJson(store.starsFile, stars);
    return _json(res, {'status': 'ok', 'starred': mine.contains(path)});
  }

  Future<void> _activity(HttpResponse res, String? u) {
    if (u == null) return _json(res, []);
    final acts = store.loadList(store.activityFile).where((a) => a is Map && a['user'] == u).take(50).toList();
    return _json(res, acts);
  }

  Future<void> _storageStats(HttpResponse res, String? u) {
    if (u == null) return _err(res, 'Not logged in', 401);
    final perms = store.loadMap(store.permsFile);
    var userSize = 0;
    var fileCount = 0;
    for (final e in store.root.listSync(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = store.relOf(e.path);
      if (rel.split('/').any((s) => s.startsWith('.'))) continue;
      final pm = perms[rel];
      if (pm is Map && pm['owner'] == u) {
        try {
          userSize += e.lengthSync();
          fileCount++;
        } catch (_) {}
      }
    }
    final total = store.treeSize(store.rootPath);
    return _json(res, {
      'your_size': fmtSize(userSize),
      'your_size_bytes': userSize,
      'your_files': fileCount,
      'total_size': fmtSize(total),
      'total_size_bytes': total,
    });
  }

  // ── share links ──────────────────────────────────────────────────────────
  Future<void> _createShareLink(HttpRequest req, HttpResponse res, String? u) async {
    if (u == null) return _err(res, 'Not logged in', 401);
    final d = await _mapBody(req);
    final path = (d['path'] as String?) ?? '';
    if (!store.canAccess(path, u)) return _err(res, 'Access denied', 403);
    final hours = (d['expires_hours'] as num?)?.toInt() ?? 24;
    final r = Random.secure();
    final token = base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256))).replaceAll('=', '');
    final links = store.loadMap(store.shareLinksFile);
    links[token] = {
      'path': path,
      'created_by': u,
      'expires': DateTime.now().millisecondsSinceEpoch / 1000 + hours * 3600,
    };
    store.saveJson(store.shareLinksFile, links);
    return _json(res, {'status': 'ok', 'token': token, 'url': '/share/$token'});
  }

  Future<void> _shareDownload(HttpRequest req, HttpResponse res, String token) async {
    final links = store.loadMap(store.shareLinksFile);
    final e = links[token];
    if (e is! Map) return _text(res, 'Link not found or expired', 404);
    final expires = (e['expires'] as num?)?.toDouble() ?? 0;
    if (DateTime.now().millisecondsSinceEpoch / 1000 > expires) {
      return _text(res, 'Link expired', 410);
    }
    final fp = store.safeJoin(store.rootPath, (e['path'] as String?) ?? '');
    if (fp == null || !FileSystemEntity.isFileSync(fp)) return _text(res, 'File not found', 404);
    await _sendFile(req, res, File(fp), p.basename(fp), true);
  }

  // ── editor / info ────────────────────────────────────────────────────────
  Future<void> _fileContent(HttpRequest req, HttpResponse res, String? u) async {
    final path = req.uri.queryParameters['path'] ?? '';
    final fp = store.safeJoin(store.rootPath, path);
    if (fp == null || !FileSystemEntity.isFileSync(fp)) return _err(res, 'Not found', 404);
    if (!store.canAccess(path, u)) return _err(res, 'Access denied', 403);
    final bytes = await File(fp).readAsBytes();
    return _json(res, {'content': utf8.decode(bytes, allowMalformed: true), 'path': path});
  }

  Future<void> _fileSave(HttpRequest req, HttpResponse res, String? u) async {
    if (u == null) return _err(res, 'Not logged in', 401);
    final d = await _mapBody(req);
    final path = (d['path'] as String?) ?? '';
    final fp = store.safeJoin(store.rootPath, path);
    if (fp == null || p.basename(fp).startsWith('.') || !FileSystemEntity.isFileSync(fp)) {
      return _err(res, 'Invalid path');
    }
    final pe = _permEntry(path);
    if (pe['owner'] != null && pe['owner'] != u) return _err(res, 'Not the owner', 403);
    await File(fp).writeAsString((d['content'] as String?) ?? '');
    store.logActivity(u, 'edited', path);
    return _json(res, {'status': 'ok'});
  }

  Future<void> _fileInfoApi(HttpRequest req, HttpResponse res, String? u) {
    final path = req.uri.queryParameters['path'] ?? '';
    final fp = store.safeJoin(store.rootPath, path);
    if (fp == null || FileSystemEntity.typeSync(fp) == FileSystemEntityType.notFound) {
      return _err(res, 'Not found', 404);
    }
    if (!store.canAccess(path, u)) return _err(res, 'Access denied', 403);
    final st = FileStat.statSync(fp);
    final pm = _permEntry(path);
    final stars = store.loadMap(store.starsFile);
    final starred = u != null && stars[u] is List && (stars[u] as List).contains(path);
    final notes = store.loadMap(store.notesFile);
    return _json(res, {
      'name': p.basename(fp),
      'path': path,
      'size': fmtSize(st.size),
      'size_bytes': st.size,
      'mime': lookupMimeType(fp) ?? 'application/octet-stream',
      'created': st.changed.millisecondsSinceEpoch / 1000,
      'modified': st.modified.millisecondsSinceEpoch / 1000,
      'owner': pm['owner'] ?? 'unknown',
      'visibility': pm['visibility'] ?? 'public',
      'allowed_users': pm['allowed_users'] ?? [],
      'starred': starred,
      'note_count': notes[path] is List ? (notes[path] as List).length : 0,
    });
  }

  // ── account deletion ─────────────────────────────────────────────────────
  Future<void> _deleteAccount(HttpRequest req, HttpResponse res, String? u) async {
    if (u == null) return _err(res, 'Not logged in', 401);
    final d = await _mapBody(req);
    final pw = (d['password'] as String?) ?? '';
    if (pw.isEmpty) return _err(res, 'Password required');
    final users = store.loadMap(store.usersFile);
    final rec = users[u];
    if (rec is! Map || rec['password'] != sha256Hex(pw)) return _err(res, 'Incorrect password', 401);

    var deletedFiles = 0;
    var deletedFolders = 0;
    final perms = store.loadMap(store.permsFile);
    final owned = perms.entries
        .where((e) => e.value is Map && (e.value as Map)['owner'] == u)
        .map((e) => e.key)
        .toList()
      ..sort((a, b) => '/'.allMatches(b).length.compareTo('/'.allMatches(a).length));
    for (final rel in owned) {
      final full = store.safeJoin(store.rootPath, rel);
      if (full == null || full == store.rootPath) continue;
      try {
        if (FileSystemEntity.isFileSync(full)) {
          File(full).deleteSync();
          deletedFiles++;
        } else if (FileSystemEntity.isDirectorySync(full)) {
          Directory(full).deleteSync(recursive: true);
          deletedFolders++;
        }
      } catch (_) {}
    }
    final meta = store.loadMap(store.metaFile);
    for (final rel in meta.keys.toList()) {
      if (meta[rel] == u) {
        final full = store.safeJoin(store.rootPath, rel);
        if (full != null && FileSystemEntity.isFileSync(full)) {
          try {
            File(full).deleteSync();
            deletedFiles++;
          } catch (_) {}
        }
        meta.remove(rel);
      }
    }
    store.saveJson(store.metaFile, meta);
    perms.removeWhere((_, v) => v is Map && v['owner'] == u);
    store.saveJson(store.permsFile, perms);

    for (final ext in const ['jpg', 'png', 'jpeg', 'gif', 'webp']) {
      final av = File(p.join(store.avatarsDir.path, '$u.$ext'));
      if (av.existsSync()) av.deleteSync();
    }
    store.invalidateAvatar(u);
    for (final f in [store.clipFile, store.linksFile, store.starsFile]) {
      final all = store.loadMap(f);
      if (all.remove(u) != null) store.saveJson(f, all);
    }
    final notes = store.loadMap(store.notesFile);
    for (final k in notes.keys.toList()) {
      if (notes[k] is List) {
        notes[k] = (notes[k] as List).where((n) => !(n is Map && n['user'] == u)).toList();
      }
    }
    store.saveJson(store.notesFile, notes);
    store.saveJson(store.activityFile,
        store.loadList(store.activityFile).where((a) => !(a is Map && a['user'] == u)).toList());
    final sl = store.loadMap(store.shareLinksFile)
      ..removeWhere((_, v) => v is Map && v['created_by'] == u);
    store.saveJson(store.shareLinksFile, sl);

    users.remove(u);
    store.saveJson(store.usersFile, users);
    store.destroySessionsOf(u);
    res.headers.add('Set-Cookie', 'sid=; Path=/; Max-Age=0; HttpOnly');
    return _json(res, {'status': 'ok', 'deleted_files': deletedFiles, 'deleted_folders': deletedFolders});
  }

  // ── multipart ─────────────────────────────────────────────────────────────
  Future<_Multipart> _readMultipart(HttpRequest req) async {
    final boundary = req.headers.contentType?.parameters['boundary'];
    if (boundary == null) throw const FormatException('Not a multipart request');
    final out = _Multipart();
    await for (final part in MimeMultipartTransformer(boundary).bind(req)) {
      final cd = part.headers['content-disposition'] ?? '';
      final name = _cdParam(cd, 'name') ?? '';
      final filename = _cdParam(cd, 'filename');
      if (filename != null) {
        final tmp = File(p.join(store.tmpDir.path, 'up_${DateTime.now().microsecondsSinceEpoch}_${_tmpCounter++}'));
        final sink = tmp.openWrite();
        await sink.addStream(part);
        await sink.close();
        out.files.add(_UploadedFile(name, filename.replaceAll('\\', '/').split('/').last, tmp));
      } else {
        final bytes = <int>[];
        await for (final c in part) {
          bytes.addAll(c);
        }
        final v = utf8.decode(bytes, allowMalformed: true);
        out.fields[name] = v;
        out.fieldLists.putIfAbsent(name, () => []).add(v);
      }
    }
    return out;
  }

  String? _cdParam(String header, String key) {
    final m = RegExp('(?:^|[;\\s])$key="((?:[^"\\\\]|\\\\.)*)"').firstMatch(header);
    if (m == null) return null;
    return m.group(1)!.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
  }
}

class _UploadedFile {
  _UploadedFile(this.field, this.filename, this.tmp);
  final String field;
  final String filename;
  final File tmp;
}

class _Multipart {
  final Map<String, String> fields = {};
  final Map<String, List<String>> fieldLists = {};
  final List<_UploadedFile> files = [];

  Future<void> cleanup() async {
    for (final f in files) {
      try {
        if (f.tmp.existsSync()) await f.tmp.delete();
      } catch (_) {}
    }
  }
}
