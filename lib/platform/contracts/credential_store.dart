/// Secrets stay in the system credential store, never in a blog or log file.
abstract interface class CredentialStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class UnavailableCredentialStore implements CredentialStore {
  const UnavailableCredentialStore();
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async =>
      throw UnsupportedError('当前平台尚未提供安全凭证存储。');
  @override
  Future<void> delete() async {}
}
