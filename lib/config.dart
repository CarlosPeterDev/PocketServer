import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'l10n.dart';

enum FtpMode { ftp, ftpsExplicit, ftpsImplicit }

extension FtpModeLabel on FtpMode {
  String get label => switch (this) {
        FtpMode.ftp => tr('FTP (plain)'),
        FtpMode.ftpsExplicit => tr('FTPS (explicit, AUTH TLS)'),
        FtpMode.ftpsImplicit => tr('FTPS (implicit, TLS)'),
      };
  String get scheme => this == FtpMode.ftp ? 'ftp' : 'ftps';
}

/// One user-created FTP / FTPS server.
class FtpServerConfig {
  FtpServerConfig({
    required this.id,
    required this.name,
    required this.username,
    required this.password,
    required this.port,
    this.mode = FtpMode.ftp,
    this.readOnly = false,
    this.enabled = false,
    this.anonymous = false,
    List<String>? folderIds,
    this.maxConnections = 0,
    this.speedLimitKBps = 0,
  }) : folderIds = folderIds ?? [];

  final String id;
  String name; // display name of the server
  String username; // login name
  String password;
  int port;
  FtpMode mode;
  bool readOnly;
  bool enabled; // start automatically with the app
  bool anonymous;
  int maxConnections; // 0 = default (64)
  int speedLimitKBps; // per transfer, 0 = unlimited
  List<String> folderIds; // empty = default folder; several = merged as top-level dirs

  static String newId() {
    final r = Random.secure();
    return List.generate(8, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  FtpServerConfig copy() => FtpServerConfig.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'username': username,
        'password': password,
        'port': port,
        'mode': mode.name,
        'readOnly': readOnly,
        'enabled': enabled,
        'anonymous': anonymous,
        'folderIds': folderIds,
        'maxConnections': maxConnections,
        'speedLimitKBps': speedLimitKBps,
      };

  factory FtpServerConfig.fromJson(Map<String, dynamic> j) => FtpServerConfig(
        id: j['id'] as String? ?? newId(),
        name: j['name'] as String? ?? 'FTP server',
        username: j['username'] as String? ?? 'user',
        password: j['password'] as String? ?? '',
        port: (j['port'] as num?)?.toInt() ?? 2121,
        mode: FtpMode.values.firstWhere(
          (m) => m.name == j['mode'],
          orElse: () => FtpMode.ftp,
        ),
        readOnly: j['readOnly'] as bool? ?? false,
        enabled: j['enabled'] as bool? ?? false,
        anonymous: j['anonymous'] as bool? ?? false,
        folderIds: const [],
        maxConnections: (j['maxConnections'] as num?)?.toInt() ?? 0,
        speedLimitKBps: (j['speedLimitKBps'] as num?)?.toInt() ?? 0,
      );
}

const String kDefaultFolderId = 'default';

/// A folder the user shared ("space"). The default one lives inside the app.
class SharedFolder {
  SharedFolder({required this.id, required this.name, required this.path});
  final String id;
  String name;
  String path; // empty for the built-in default folder

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'path': path};
  factory SharedFolder.fromJson(Map<String, dynamic> j) => SharedFolder(
        id: j['id'] as String? ?? FtpServerConfig.newId(),
        name: j['name'] as String? ?? 'Folder',
        path: j['path'] as String? ?? '',
      );
}

/// One WebDAV server (mount as a network drive).
class DavConfig {
  DavConfig({
    required this.id,
    required this.name,
    required this.username,
    required this.password,
    this.port = 8080,
    this.folderId = kDefaultFolderId,
    this.readOnly = false,
    this.enabled = false,
  });
  final String id;
  String name;
  String username;
  String password;
  int port;
  String folderId;
  bool readOnly;
  bool enabled;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'username': username,
        'password': password,
        'port': port,
        'folderId': folderId,
        'readOnly': readOnly,
        'enabled': enabled,
      };
  factory DavConfig.fromJson(Map<String, dynamic> j) => DavConfig(
        id: j['id'] as String? ?? FtpServerConfig.newId(),
        name: j['name'] as String? ?? 'WebDAV',
        username: j['username'] as String? ?? 'user',
        password: j['password'] as String? ?? '',
        port: (j['port'] as num?)?.toInt() ?? 8080,
        folderId: kDefaultFolderId,
        readOnly: j['readOnly'] as bool? ?? false,
        enabled: j['enabled'] as bool? ?? false,
      );
}

/// One web file hub (its own port and folder).
class WebHubConfig {
  WebHubConfig({
    required this.id,
    required this.name,
    this.port = 2011,
    this.folderId = kDefaultFolderId,
    this.enabled = true,
  });
  final String id;
  String name;
  int port;
  String folderId;
  bool enabled;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'port': port, 'folderId': folderId, 'enabled': enabled};
  factory WebHubConfig.fromJson(Map<String, dynamic> j) => WebHubConfig(
        id: j['id'] as String? ?? FtpServerConfig.newId(),
        name: j['name'] as String? ?? 'Web hub',
        port: (j['port'] as num?)?.toInt() ?? 2011,
        folderId: kDefaultFolderId,
        enabled: j['enabled'] as bool? ?? true,
      );
}

class AppConfig {
  AppConfig({List<SharedFolder>? folders, List<WebHubConfig>? webHubs, List<FtpServerConfig>? ftp, List<DavConfig>? dav})
      : dav = dav ?? [],
        folders = folders ?? [],
        webHubs = webHubs ?? [WebHubConfig(id: 'web-main', name: 'Web hub')],
        ftp = ftp ?? [];

  List<SharedFolder> folders; // user added spaces (default is implicit)
  List<WebHubConfig> webHubs;
  List<FtpServerConfig> ftp;
  List<DavConfig> dav;

  /// Resolve a folder id to a real directory path.
  String pathOf(String id, String defaultPath) {
    return defaultPath; // single shared folder: PocketServer's own folder
  }

  String nameOf(String id) => tr('App folder');

  Map<String, dynamic> toJson() => {
        'folders': folders.map((e) => e.toJson()).toList(),
        'webHubs': webHubs.map((e) => e.toJson()).toList(),
        'ftp': ftp.map((e) => e.toJson()).toList(),
        'dav': dav.map((e) => e.toJson()).toList(),
      };

  factory AppConfig.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String k, T Function(Map<String, dynamic>) f) =>
        ((j[k] as List?) ?? []).map((e) => f(Map<String, dynamic>.from(e as Map))).toList();
    final hubs = list('webHubs', WebHubConfig.fromJson);
    return AppConfig(
      folders: const [], // folder choice was removed: every server shares the app folder
      webHubs: j.containsKey('webHubs') ? hubs : null,
      ftp: list('ftp', FtpServerConfig.fromJson),
      dav: list('dav', DavConfig.fromJson),
    );
  }

  String encode() => jsonEncode(toJson());
  factory AppConfig.decode(String s) =>
      AppConfig.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map));

  static Future<AppConfig> load(File f) async {
    try {
      if (await f.exists()) return AppConfig.decode(await f.readAsString());
    } catch (_) {}
    return AppConfig();
  }

  Future<void> save(File f) async {
    await f.parent.create(recursive: true);
    await f.writeAsString(encode());
  }
}

/// Live status published by the server host (and sent across isolates as a Map).
class HostStatus {
  HostStatus({this.ips = const [], Map<String, FtpStatus>? web, Map<String, FtpStatus>? ftp, Map<String, FtpStatus>? dav, this.stats = const {}})
      : web = web ?? {},
        dav = dav ?? {},
        ftp = ftp ?? {};

  final List<String> ips;
  final Map<String, FtpStatus> web; // web hub id -> status
  final Map<String, FtpStatus> ftp;
  final Map<String, FtpStatus> dav;
  final Map<String, dynamic> stats; // see Stats.toJson

  bool get anyRunning => web.values.any((e) => e.running) || ftp.values.any((e) => e.running) || dav.values.any((e) => e.running);

  Map<String, dynamic> toJson() => {
        'ips': ips,
        'web': web.map((k, v) => MapEntry(k, v.toJson())),
        'ftp': ftp.map((k, v) => MapEntry(k, v.toJson())),
        'dav': dav.map((k, v) => MapEntry(k, v.toJson())),
        'stats': stats,
      };

  factory HostStatus.fromJson(Map<String, dynamic> j) {
    Map<String, FtpStatus> m(String k) => ((j[k] as Map?) ?? {}).map((a, v) =>
        MapEntry(a as String, FtpStatus.fromJson(Map<String, dynamic>.from(v as Map))));
    return HostStatus(ips: ((j['ips'] as List?) ?? []).cast<String>(), web: m('web'), ftp: m('ftp'),
        dav: m('dav'),
        stats: j['stats'] is Map ? Map<String, dynamic>.from(j['stats'] as Map) : const {});
  }
}

class FtpStatus {
  FtpStatus({this.running = false, this.error, this.connections = 0});
  final bool running;
  final String? error;
  final int connections;

  Map<String, dynamic> toJson() =>
      {'running': running, 'error': error, 'connections': connections};
  factory FtpStatus.fromJson(Map<String, dynamic> j) => FtpStatus(
        running: j['running'] as bool? ?? false,
        error: j['error'] as String?,
        connections: (j['connections'] as num?)?.toInt() ?? 0,
      );
}

Future<List<String>> localIps() async {
  final out = <String>[];
  try {
    for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final a in ni.addresses) {
        if (!a.isLoopback) out.add(a.address);
      }
    }
  } catch (_) {}
  return out;
}
