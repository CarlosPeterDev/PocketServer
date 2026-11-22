import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'l10n_ar.dart';

/// Current UI language ('en' or 'ar'). Follows the phone the first time, then the user's choice.
class Lang {
  static String code = 'en';
  static final ValueNotifier<Locale> locale = ValueNotifier(const Locale('en'));

  static bool get isAr => code == 'ar';

  /// Arabic phones get Arabic, everything else gets English.
  static String deviceDefault() {
    try {
      return PlatformDispatcher.instance.locale.languageCode.toLowerCase() == 'ar' ? 'ar' : 'en';
    } catch (_) {
      return 'en';
    }
  }

  static void set(String c) {
    code = c == 'ar' ? 'ar' : 'en';
    locale.value = Locale(code);
  }
}

/// Translate an English UI string. `{name}` placeholders are replaced from [args].
/// Strings with no Arabic entry fall back to English (and a unit test makes sure none are missing).
String tr(String en, [Map<String, Object?>? args]) {
  var s = Lang.isAr ? (kArabic[en] ?? en) : en;
  if (args != null) {
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  }
  return s;
}

/// Rebuild every widget after a language switch (strings are read through [tr], not through inherited widgets).
void rebuildApp() {
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}

/// Apply [code], rebuild the UI once the new locale is in place.
void switchLanguage(String code) {
  Lang.set(code);
  WidgetsBinding.instance.addPostFrameCallback((_) => rebuildApp());
  WidgetsBinding.instance.scheduleFrame();
}
