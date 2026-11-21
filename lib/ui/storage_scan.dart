import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

const _cats = <String, Set<String>>{
  'Video': {'.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v', '.3gp', '.ts', '.mpg', '.mpeg'},
  'Audio': {'.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a', '.opus', '.wma'},
  'Images': {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic', '.svg', '.tiff'},
  'Documents': {'.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt', '.md', '.csv', '.odt', '.rtf'},
  'Archives': {'.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz', '.iso'},
  'Apps': {'.apk', '.aab', '.exe', '.msi', '.dmg', '.deb', '.ipa', '.appimage'},
};

class StorageReport {
  StorageReport(this.totalBytes, this.files, this.folders, this.byCategory, this.countByCategory, this.largest, this.truncated);
  final int totalBytes;
  final int files;
  final int folders;
  final Map<String, int> byCategory;
  final Map<String, int> countByCategory;
  final List<({String name, String folder, int size})> largest;
  final bool truncated;
}

/// Scans [folders] (name, path) in a background isolate. Capped at 300k entries.
Future<StorageReport> scanStorage(List<(String, String)> folders) {
  return Isolate.run(() {
    var total = 0, files = 0, dirs = 0, seen = 0;
    var truncated = false;
    final by = <String, int>{};
    final cnt = <String, int>{};
    final big = <({String name, String folder, int size})>[];
    for (final (label, path) in folders) {
      final d = Directory(path);
      if (!d.existsSync()) continue;
      try {
        for (final e in d.listSync(recursive: true, followLinks: false)) {
          if (++seen > 300000) {
            truncated = true;
            break;
          }
          final rel = p.relative(e.path, from: path);
          if (rel.split(RegExp(r'[\\/]')).any((s) => s.startsWith('.'))) continue;
          if (e is Directory) {
            dirs++;
            continue;
          }
          if (e is! File) continue;
          int size;
          try {
            size = e.lengthSync();
          } catch (_) {
            continue;
          }
          files++;
          total += size;
          final ext = p.extension(e.path).toLowerCase();
          var cat = 'Other';
          for (final en in _cats.entries) {
            if (en.value.contains(ext)) {
              cat = en.key;
              break;
            }
          }
          by[cat] = (by[cat] ?? 0) + size;
          cnt[cat] = (cnt[cat] ?? 0) + 1;
          big.add((name: p.basename(e.path), folder: label, size: size));
          if (big.length > 400) {
            big.sort((a, b) => b.size.compareTo(a.size));
            big.removeRange(40, big.length);
          }
        }
      } catch (_) {}
      if (truncated) break;
    }
    big.sort((a, b) => b.size.compareTo(a.size));
    return StorageReport(total, files, dirs, by, cnt, big.take(10).toList(), truncated);
  });
}

String fmtBytes(num b) {
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = b.toDouble();
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${u[i]}';
}
