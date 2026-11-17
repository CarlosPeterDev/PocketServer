import 'package:flutter_test/flutter_test.dart';
import 'package:pocketserver_contracts/pocketserver_contracts.dart';
import 'package:pocketserver_flutter/main.dart';

void main() {
  testWidgets('shows the supplied host details', (tester) async {
    await tester.pumpWidget(
      PocketServerApp(
        readStorage: () async => 2 * 1024 * 1024 * 1024,
        host: const HostDiagnostics(
          platform: HostPlatform.android,
          operatingSystemVersion: 'Android 8.0',
          logicalProcessors: 8,
        ),
      ),
    );

    expect(find.text('Host diagnostics'), findsOneWidget);
    expect(find.text('Android'), findsOneWidget);
    expect(find.text('Android 8.0'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('2.00 GiB'), findsOneWidget);
  });
}
