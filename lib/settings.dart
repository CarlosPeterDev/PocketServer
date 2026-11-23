import 'dart:convert';
import 'dart:io';

/// Small per-device settings: chosen language and which privacy policy version was accepted.
class AppSettings {
  AppSettings({this.lang, this.privacyVersion = 0, this.introSeen = false});

  /// 'en' or 'ar'. null = never chosen (follow the phone's language).
  String? lang;
  int privacyVersion;

  /// The welcome slides were shown once.
  bool introSeen;

  /// Bump when privacy.json changes in a way users must re-accept.
  static const int kPrivacyVersion = 1;

  bool get privacyAccepted => privacyVersion >= kPrivacyVersion;

  static Future<AppSettings> load(File f) async {
    try {
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map;
        return AppSettings(
          lang: j['lang'] as String?,
          privacyVersion: (j['privacyVersion'] as num?)?.toInt() ?? 0,
          introSeen: j['introSeen'] as bool? ?? false,
        );
      }
    } catch (_) {}
    return AppSettings();
  }

  Future<void> save(File f) async {
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode({'lang': lang, 'privacyVersion': privacyVersion, 'introSeen': introSeen}));
  }
}
