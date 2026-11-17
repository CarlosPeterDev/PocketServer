import 'package:pocketserver_contracts/pocketserver_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('recognizes the supported hosts and handles other OS identifiers', () {
    expect(HostPlatform.fromOperatingSystem('android'), HostPlatform.android);
    expect(HostPlatform.fromOperatingSystem('windows'), HostPlatform.windows);
    for (final os in ['linux', 'macos', 'ios', '']) {
      expect(HostPlatform.fromOperatingSystem(os), HostPlatform.unsupported);
    }
  });

  test('reads diagnostics from the current host', () {
    final host = HostDiagnostics.current();
    expect(host.logicalProcessors, greaterThan(0));
    expect(host.operatingSystemVersion, isNotEmpty);
  });
}
