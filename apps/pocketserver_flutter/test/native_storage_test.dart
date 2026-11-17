import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketserver_flutter/native_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.pocketserver.app/host_diagnostics');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('returns the bytes reported by the native channel', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getAvailableStorageBytes');
      return 8000000000;
    });
    expect(await readAvailableStorage(), 8000000000);
  });

  test('rejects a negative native storage reading', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => -1);
    await expectLater(
      readAvailableStorage(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'invalid_storage_response',
        ),
      ),
    );
  });
}
