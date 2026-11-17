import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketserver_flutter/static_site_card.dart';

void main() {
  testWidgets('displays the native address and clears it when stopped', (
    tester,
  ) async {
    const channel = MethodChannel('com.pocketserver.app/static_site');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    const address = 'http://127.0.0.1:43821/';
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'chooseAndStart' ? address : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StaticSiteCard())),
    );

    await tester.tap(find.text('Choose HTML file'));
    await tester.pumpAndSettle();
    expect(find.text(address), findsOneWidget);

    await tester.tap(find.text('Stop hosting'));
    await tester.pumpAndSettle();
    expect(find.text(address), findsNothing);
    expect(calls, ['chooseAndStart', 'stop']);
  });
}
