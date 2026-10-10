import 'package:flutter/services.dart';
import 'package:blog_studio/platform/contracts/credential_store.dart';

class MacCredentialStore implements CredentialStore {
  const MacCredentialStore();
  static const _channel = MethodChannel('inkjian/credentials');
  @override
  Future<String?> read() => _channel.invokeMethod<String>('read');
  @override
  Future<void> write(String value) =>
      _channel.invokeMethod<void>('write', value);
  @override
  Future<void> delete() => _channel.invokeMethod<void>('delete');
}
