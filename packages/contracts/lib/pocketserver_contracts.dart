import 'dart:io';

/// Supported PocketServer targets, as detected by the running Dart VM.
enum HostPlatform {
  android,
  windows,
  unsupported;

  static HostPlatform fromOperatingSystem(String name) => switch (name) {
    'android' => android,
    'windows' => windows,
    _ => unsupported,
  };
}

final class HostDiagnostics {
  const HostDiagnostics({
    required this.platform,
    required this.operatingSystemVersion,
    required this.logicalProcessors,
  });

  factory HostDiagnostics.current() => HostDiagnostics(
    platform: HostPlatform.fromOperatingSystem(Platform.operatingSystem),
    operatingSystemVersion: Platform.operatingSystemVersion,
    logicalProcessors: Platform.numberOfProcessors,
  );

  final HostPlatform platform;
  final String operatingSystemVersion;
  final int logicalProcessors;
}
