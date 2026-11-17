import 'package:flutter/services.dart';

const _channel = MethodChannel('com.pocketserver.app/host_diagnostics');

/// Bytes available to the current user on the app-data volume.
Future<int> readAvailableStorage() async {
  final bytes = await _channel.invokeMethod<int>('getAvailableStorageBytes');
  if (bytes == null || bytes < 0) {
    throw PlatformException(code: 'invalid_storage_response');
  }
  return bytes;
}
