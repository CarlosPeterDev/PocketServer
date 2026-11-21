import 'dart:convert';
import 'dart:io';
import 'dart:math';

enum FtpMode { ftp, ftpsExplicit, ftpsImplicit }

extension FtpModeLabel on FtpMode {
  String get label => switch (this) {
        FtpMode.ftp => 'FTP (plain)',
        FtpMode.ftpsExplicit => 'FTPS (explicit, AUTH TLS)',
        FtpMode.ftpsImplicit => 'FTPS (implicit, TLS)',
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
  });

  final String id;
  String name; // display name of the server
  String username; // login name
  String password;
  int port;
  FtpMode mode;
  bool readOnly;
  bool enabled; // start automatically with the app
  bool anonymous;

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
      );
}

class AppConfig {
  AppConfig({
    this.webPort = 2011,
    this.webEnabled = true,
    this.storageDir = '',
    List<FtpServerConfig>? ftp,
  }) : ftp = ftp ?? [];

  int webPort;
  bool webEnabled; // start web server automatically
  String storageDir; // resolved at runtime when empty
  List<FtpServerConfig> ftp;

  Map<String, dynamic> toJson() => {
        'webPort': webPort,
        'webEnabled': webEnabled,
        'storageDir': storageDir,
        'ftp': ftp.map((e) => e.toJson()).toList(),
      };

  factory AppConfig.fromJson(Map<String, dynamic> j) => AppConfig(
        webPort: (j['webPort'] as num?)?.toInt() ?? 2011,
        webEnabled: j['webEnabled'] as bool? ?? true,
        storageDir: j['storageDir'] as String? ?? '',
        ftp: ((j['ftp'] as List?) ?? [])
            .map((e) => FtpServerConfig.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

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
  HostStatus({
    this.webRunning = false,
    this.webError,
    this.ips = const [],
    Map<String, FtpStatus>? ftp,
  }) : ftp = ftp ?? {};

  final bool webRunning;
  final String? webError;
  final List<String> ips;
  final Map<String, FtpStatus> ftp;

  Map<String, dynamic> toJson() => {
        'webRunning': webRunning,
        'webError': webError,
        'ips': ips,
        'ftp': ftp.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory HostStatus.fromJson(Map<String, dynamic> j) => HostStatus(
        webRunning: j['webRunning'] as bool? ?? false,
        webError: j['webError'] as String?,
        ips: ((j['ips'] as List?) ?? []).cast<String>(),
        ftp: ((j['ftp'] as Map?) ?? {}).map((k, v) =>
            MapEntry(k as String, FtpStatus.fromJson(Map<String, dynamic>.from(v as Map)))),
      );
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
