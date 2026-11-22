import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketserver/l10n.dart';
import 'package:pocketserver/l10n_ar.dart';

String _unesc(String s) => s.replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1] == 'n' ? '\n' : m[1]!);

void main() {
  test('every tr() string has an Arabic translation', () {
    final lit = r'''(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")''';
    final direct = RegExp(r'\btr\(\s*' + lit);
    final ternary = RegExp(r'\btr\([^' "'" r'"\n]*\?\s*' + lit + r'\s*:\s*' + lit);
    final missing = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('l10n_ar.dart') || f.path.endsWith('web_ui.dart')) continue;
      final t = f.readAsStringSync();
      final keys = <String>[
        for (final m in direct.allMatches(t)) _unesc(m[1] ?? m[2]!),
        for (final m in ternary.allMatches(t)) ...[_unesc(m[1] ?? m[2]!), _unesc(m[3] ?? m[4]!)],
      ];
      for (final k in keys) {
        if (!kArabic.containsKey(k)) missing.add(k);
      }
    }
    expect(missing, isEmpty);
  });

  test('placeholders survive translation', () {
    final ph = RegExp(r'\{[a-z]+\}');
    for (final e in kArabic.entries) {
      expect(ph.allMatches(kArabic[e.key]!).map((m) => m[0]).toSet(), ph.allMatches(e.key).map((m) => m[0]).toSet(),
          reason: e.key);
    }
  });

  test('tr() switches language and fills placeholders', () {
    Lang.set('en');
    expect(tr('Delete "{name}"?', {'name': 'X'}), 'Delete "X"?');
    Lang.set('ar');
    expect(tr('Delete "{name}"?', {'name': 'X'}), 'حذف "X"؟');
    expect(tr('not translated'), 'not translated');
    Lang.set('en');
  });

  test('privacy policy exists in both languages with the same sections', () {
    final d = jsonDecode(File('assets/privacy.json').readAsStringSync()) as Map;
    final en = d['en'] as Map, ar = d['ar'] as Map;
    expect((en['sections'] as List).length, (ar['sections'] as List).length);
    expect(ar['title'], isNotEmpty);
  });
}
