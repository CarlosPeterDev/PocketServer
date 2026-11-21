import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

const Set<String> kTextExts = {
  '.py', '.txt', '.md', '.js', '.ts', '.jsx', '.tsx', '.css', '.html', '.htm',
  '.json', '.xml', '.yaml', '.yml', '.csv', '.sh', '.c', '.cpp', '.h', '.java',
  '.php', '.rb', '.go', '.rs', '.sql', '.log', '.ini', '.toml', '.env', '.vue',
  '.svelte', '.swift', '.kt', '.dart', '.r', '.lua', '.pl', '.pm', '.cfg',
  '.conf', '.properties', '.gradle',
};

String sha256Hex(String s) => sha256.convert(utf8.encode(s)).toString();

String fmtSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

/// Disk-backed state shared by the web server (and the FTP servers' root).
/// All JSON files use synchronous IO so request handlers never interleave
/// a read-modify-write.
class ShareStore {
  ShareStore(String rootPath)
      : root = Directory(p.normalize(p.absolute(rootPath))) {
    root.createSync(recursive: true);
    avatarsDir.createSync(recursive: true);
    tmpDir.createSync(recursive: true);
  }

  final Directory root;
  final Map<String, String?> _avatarCache = {};

  String get rootPath => root.path;
  Directory get avatarsDir => Directory(p.join(root.path, '.avatars'));
  Directory get tmpDir => Directory(p.join(root.path, '.tmp'));
  File _f(String n) => File(p.join(root.path, n));
  File get metaFile => _f('.metadata.json');
  File get clipFile => _f('.clipboards.json');
  File get usersFile => _f('.users.json');
  File get permsFile => _f('.permissions.json');
  File get linksFile => _f('.links.json');
  File get notesFile => _f('.notes.json');
  File get starsFile => _f('.stars.json');
  File get activityFile => _f('.activity.json');
  File get shareLinksFile => _f('.share_links.json');
  File get sessionsFile => _f('.sessions.json');

  // ── JSON helpers ──────────────────────────────────────────────────────────
  dynamic loadJson(File f, dynamic fallback) {
    try {
      if (!f.existsSync()) return fallback;
      return jsonDecode(f.readAsStringSync());
    } catch (_) {
      return fallback;
    }
  }

  Map<String, dynamic> loadMap(File f) {
    final v = loadJson(f, <String, dynamic>{});
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  List<dynamic> loadList(File f) {
    final v = loadJson(f, <dynamic>[]);
    return v is List ? List<dynamic>.from(v) : <dynamic>[];
  }

  void saveJson(File f, Object? data) {
    try {
      f.writeAsStringSync(jsonEncode(data));
    } catch (e) {
      // ignore: avoid_print
      print('saveJson error: $e');
    }
  }

  // ── Paths ─────────────────────────────────────────────────────────────────
  String? safeJoin(String base, String path) {
    var rel = path.replaceAll('\\', '/');
    rel = rel.replaceAll(RegExp(r'^/+|/+$'), '');
    rel = rel.replaceAll(RegExp(r'/{2,}'), '/');
    final b = p.normalize(p.absolute(base));
    if (rel.isEmpty) return b;
    final fin = p.normalize(p.absolute(p.join(b, rel)));
    return (fin == b || p.isWithin(b, fin)) ? fin : null;
  }

  /// Path relative to the storage root, always with forward slashes.
  String relOf(String full) =>
      p.relative(full, from: root.path).replaceAll('\\', '/');

  int treeSize(String path) {
    var total = 0;
    try {
      for (final e in Directory(path).listSync(followLinks: false)) {
        if (p.basename(e.path).startsWith('.')) continue;
        if (e is Directory) {
          total += treeSize(e.path);
        } else if (e is File) {
          total += e.lengthSync();
        }
      }
    } catch (_) {}
    return total;
  }

  String usage() => fmtSize(treeSize(root.path));

  // ── Users & sessions ─────────────────────────────────────────────────────
  String? sessionUser(String? sid) {
    if (sid == null || sid.isEmpty) return null;
    final s = loadMap(sessionsFile);
    final u = s[sid];
    if (u is! String) return null;
    final users = loadMap(usersFile);
    return users.containsKey(u) ? u : null;
  }

  String createSession(String username) {
    final r = Random.secure();
    final sid = base64Url
        .encode(List<int>.generate(24, (_) => r.nextInt(256)))
        .replaceAll('=', '');
    final s = loadMap(sessionsFile);
    s[sid] = username;
    saveJson(sessionsFile, s);
    return sid;
  }

  void destroySession(String? sid) {
    if (sid == null) return;
    final s = loadMap(sessionsFile);
    if (s.remove(sid) != null) saveJson(sessionsFile, s);
  }

  void destroySessionsOf(String username) {
    final s = loadMap(sessionsFile)..removeWhere((_, v) => v == username);
    saveJson(sessionsFile, s);
  }

  String defaultPrivacy(String? username) {
    if (username == null) return 'public';
    final users = loadMap(usersFile);
    final u = users[username];
    if (u is Map && u['default_privacy'] is String) return u['default_privacy'] as String;
    return 'public';
  }

  // ── Permissions ──────────────────────────────────────────────────────────
  bool canAccess(String relPath, String? viewer, [Map<String, dynamic>? perms]) {
    perms ??= loadMap(permsFile);
    final raw = perms[relPath];
    final pm = raw is Map ? raw : const {};
    final vis = (pm['visibility'] as String?) ?? 'public';
    if (vis == 'public') return true;
    if (viewer != null && viewer == pm['owner']) return true;
    if (vis == 'private') return false;
    if (vis == 'selected') {
      final allowed = (pm['allowed_users'] as List?) ?? const [];
      return viewer != null && allowed.contains(viewer);
    }
    return true;
  }

  // ── File type info ───────────────────────────────────────────────────────
  Map<String, String> fileInfo(String name, bool isFolder) {
    if (isFolder) {
      return {
        'type': 'folder', 'icon': 'fa-folder', 'color': 'text-yellow-500',
        'bg': 'bg-yellow-50 dark:bg-yellow-900/20',
      };
    }
    final mime = lookupMimeType(name);
    final ext = p.extension(name).toLowerCase();
    final m = <String, String>{
      'type': 'other', 'icon': 'fa-file', 'color': 'text-slate-400',
      'bg': 'bg-slate-100 dark:bg-slate-700',
    };
    if (mime != null) {
      if (mime.startsWith('video')) {
        m.addAll({'type': 'video', 'icon': 'fa-file-video', 'color': 'text-pink-500', 'bg': 'bg-pink-50 dark:bg-pink-900/20'});
      } else if (mime.startsWith('image')) {
        m.addAll({'type': 'image', 'icon': 'fa-file-image', 'color': 'text-purple-500', 'bg': 'bg-purple-50 dark:bg-purple-900/20'});
      } else if (mime.startsWith('audio')) {
        m.addAll({'type': 'audio', 'icon': 'fa-music', 'color': 'text-amber-500', 'bg': 'bg-amber-50 dark:bg-amber-900/20'});
      } else if (mime == 'application/pdf') {
        m.addAll({'type': 'pdf', 'icon': 'fa-file-pdf', 'color': 'text-red-500', 'bg': 'bg-red-50 dark:bg-red-900/20'});
      } else if (mime.startsWith('text') || kTextExts.contains(ext)) {
        m.addAll({'type': 'text', 'icon': 'fa-file-code', 'color': 'text-cyan-500', 'bg': 'bg-cyan-50 dark:bg-cyan-900/20'});
      }
    } else if (kTextExts.contains(ext)) {
      m.addAll({'type': 'text', 'icon': 'fa-file-code', 'color': 'text-cyan-500', 'bg': 'bg-cyan-50 dark:bg-cyan-900/20'});
    }
    if (const ['.zip', '.tar', '.gz', '.rar', '.7z'].contains(ext)) {
      m.addAll({'type': 'zip', 'icon': 'fa-file-zipper', 'color': 'text-orange-500', 'bg': 'bg-orange-50 dark:bg-orange-900/20'});
    }
    if (const ['.doc', '.docx'].contains(ext)) {
      m.addAll({'type': 'doc', 'icon': 'fa-file-word', 'color': 'text-blue-600', 'bg': 'bg-blue-50 dark:bg-blue-900/20'});
    }
    if (const ['.xls', '.xlsx', '.csv'].contains(ext)) {
      m.addAll({'type': 'spreadsheet', 'icon': 'fa-file-excel', 'color': 'text-green-600', 'bg': 'bg-green-50 dark:bg-green-900/20'});
    }
    if (const ['.ppt', '.pptx'].contains(ext)) {
      m.addAll({'type': 'slide', 'icon': 'fa-file-powerpoint', 'color': 'text-orange-600', 'bg': 'bg-orange-50 dark:bg-orange-900/20'});
    }
    if (ext == '.apk') {
      m.addAll({'type': 'apk', 'icon': 'fa-android', 'color': 'text-green-500', 'bg': 'bg-green-50 dark:bg-green-900/20'});
    }
    return m;
  }

  // ── Avatars ──────────────────────────────────────────────────────────────
  String? userAvatar(String? username) {
    if (username == null || username.isEmpty) return null;
    if (_avatarCache.containsKey(username)) return _avatarCache[username];
    String? out;
    for (final ext in const ['jpg', 'png']) {
      final f = File(p.join(avatarsDir.path, '$username.$ext'));
      if (f.existsSync()) {
        final mime = ext == 'jpg' ? 'image/jpeg' : 'image/png';
        out = 'data:$mime;base64,${base64Encode(f.readAsBytesSync())}';
        break;
      }
    }
    _avatarCache[username] = out;
    return out;
  }

  void invalidateAvatar(String username) => _avatarCache.remove(username);

  // ── Activity log ─────────────────────────────────────────────────────────
  void logActivity(String user, String action, String target) {
    final acts = loadList(activityFile);
    acts.insert(0, {
      'user': user, 'action': action, 'target': target,
      'ts': DateTime.now().millisecondsSinceEpoch / 1000,
    });
    saveJson(activityFile, acts.take(200).toList());
  }

  // ── File listing ─────────────────────────────────────────────────────────
  List<Map<String, dynamic>> contentData(
      String currentPath, String sortBy, String query, String? viewer) {
    final perms = loadMap(permsFile);
    currentPath = currentPath.replaceAll(RegExp(r'^/+|/+$'), '');
    final searchRoot = safeJoin(root.path, currentPath);
    if (searchRoot == null || !Directory(searchRoot).existsSync()) return [];
    final entries = <MapEntry<String, FileSystemEntity>>[]; // rel -> entity
    try {
      if (query.isNotEmpty) {
        final q = query.toLowerCase();
        for (final e in root.listSync(recursive: true, followLinks: false)) {
          final rel = relOf(e.path);
          if (rel.split('/').any((s) => s.startsWith('.'))) continue;
          if (p.basename(e.path).toLowerCase().contains(q)) {
            entries.add(MapEntry(rel, e));
          }
        }
      } else {
        for (final e in Directory(searchRoot).listSync(followLinks: false)) {
          final name = p.basename(e.path);
          if (name.startsWith('.')) continue;
          entries.add(MapEntry(currentPath.isEmpty ? name : '$currentPath/$name', e));
        }
      }
    } catch (_) {}
    final items = <Map<String, dynamic>>[];
    for (final en in entries) {
      try {
        final rel = en.key;
        if (!canAccess(rel, viewer, perms)) continue;
        final isDir = en.value is Directory;
        final st = en.value.statSync();
        final name = p.basename(en.value.path);
        final pmRaw = perms[rel];
        final pm = pmRaw is Map ? pmRaw : const {};
        final owner = pm['owner'] as String?;
        items.add({
          'name': name,
          'path': rel,
          'size': isDir ? '-' : fmtSize(st.size),
          'size_bytes': st.size,
          'date': st.modified.millisecondsSinceEpoch / 1000,
          'is_folder': isDir,
          'owner': owner,
          'visibility': pm['visibility'] ?? 'public',
          'owner_avatar': userAvatar(owner),
          ...fileInfo(name, isDir),
        });
      } catch (_) {}
    }
    int folderFirst(Map a, Map b) =>
        (a['is_folder'] == b['is_folder']) ? 0 : (a['is_folder'] == true ? -1 : 1);
    items.sort((a, b) {
      final f = folderFirst(a, b);
      if (f != 0) return f;
      switch (sortBy) {
        case 'name':
          return (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase());
        case 'size':
          return (b['size_bytes'] as int).compareTo(a['size_bytes'] as int);
        default:
          return (b['date'] as double).compareTo(a['date'] as double);
      }
    });
    return items;
  }

  // ── Text helpers ─────────────────────────────────────────────────────────
  /// Valid UTF-8 without BOM, re-encoding from latin-1 when needed.
  List<int> asCleanUtf8(List<int> raw) {
    List<int> clean;
    try {
      utf8.decode(raw);
      clean = raw;
    } on FormatException {
      clean = utf8.encode(latin1.decode(raw));
    }
    if (clean.length >= 3 && clean[0] == 0xEF && clean[1] == 0xBB && clean[2] == 0xBF) {
      clean = clean.sublist(3);
    }
    return clean;
  }
}
