import 'package:blog_studio/models/publishing.dart';
import 'package:blog_studio/platform/contracts/credential_store.dart';
import 'package:blog_studio/services/publishing/github_transport.dart';

class GitHubAppSettings {
  const GitHubAppSettings({
    this.clientId = const String.fromEnvironment(
      'INKJIAN_GITHUB_CLIENT_ID',
      defaultValue: 'Iv23liMycMnHN9ykBFne',
    ),
    this.slug = const String.fromEnvironment(
      'INKJIAN_GITHUB_APP_SLUG',
      defaultValue: 'inkjian-publisher',
    ),
  });
  final String clientId, slug;
  bool get configured =>
      clientId.isNotEmpty && RegExp(r'^[a-z0-9-]+$').hasMatch(slug);
  Uri get installationUri =>
      Uri.https('github.com', '/apps/$slug/installations/new');
}

class GitHubAuth {
  GitHubAuth({
    required this.store,
    GitHubTransport? transport,
    this.settings = const GitHubAppSettings(),
  }) : transport = transport ?? HttpGitHubTransport();
  final CredentialStore store;
  final GitHubTransport transport;
  final GitHubAppSettings settings;
  GitHubCredentials? _credentials;
  Future<String> token() async {
    if (_credentials == null || _credentials!.expired) {
      throw const PublishingException('请连接 GitHub 账号后继续。');
    }
    return _credentials!.token;
  }

  Future<GitHubAccount?> restore() async {
    final raw = await store.read();
    if (raw == null) return null;
    try {
      _credentials = GitHubCredentials.decode(raw);
    } on FormatException {
      await disconnect();
      return null;
    }
    if (_credentials!.expired) {
      await disconnect();
      return null;
    }
    try {
      return await account();
    } on GitHubFailure catch (e) {
      if (e.status != 401) rethrow;
      await disconnect();
      return null;
    }
  }

  Future<GitHubAccount> account() async {
    final data = await transport.request(
      'GET',
      Uri.https('api.github.com', '/user'),
      token: await token(),
    );
    return GitHubAccount(data['login'] as String);
  }

  Future<DeviceAuthorization> begin() async {
    if (!settings.configured) {
      throw const PublishingException(
        '此构建尚未配置 GitHub 登录。开发者需要注册 GitHub App 后重新构建。',
      );
    }
    final data = await transport.request(
      'POST',
      Uri.https('github.com', '/login/device/code'),
      body: {'client_id': settings.clientId},
    );
    if (data['error'] != null) {
      throw const PublishingException('无法开始 GitHub 授权，请检查应用是否启用了设备登录。');
    }
    return DeviceAuthorization(
      code: data['device_code'] as String,
      userCode: data['user_code'] as String,
      expiresAt: DateTime.now().add(
        Duration(seconds: data['expires_in'] as int),
      ),
      interval: Duration(seconds: data['interval'] as int),
    );
  }

  Future<GitHubAccount> complete(
    DeviceAuthorization device, {
    required bool Function() cancelled,
    Future<void> Function(Duration)? wait,
  }) async {
    var interval = device.interval;
    while (DateTime.now().isBefore(device.expiresAt)) {
      if (cancelled()) throw PublishCancelled();
      await (wait ?? Future<void>.delayed)(interval);
      if (cancelled()) throw PublishCancelled();
      final data = await transport.request(
        'POST',
        Uri.https('github.com', '/login/oauth/access_token'),
        body: {
          'client_id': settings.clientId,
          'device_code': device.code,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        },
      );
      if (cancelled()) throw PublishCancelled();
      switch (data['error']) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          interval += const Duration(seconds: 5);
          continue;
        case 'access_denied':
          throw const PublishingException('GitHub 授权已取消。');
        case 'expired_token':
          throw const PublishingException('授权码已过期，请重新连接。');
        case null:
          break;
        default:
          throw const PublishingException('GitHub 授权未完成，请重新连接。');
      }
      if (data['access_token'] is! String ||
          (data['access_token'] as String).isEmpty) {
        throw const PublishingException('GitHub 未返回有效授权，请重试。');
      }
      _credentials = GitHubCredentials(
        data['access_token'] as String,
        data['expires_in'] is int
            ? DateTime.now().add(Duration(seconds: data['expires_in']))
            : null,
      );
      final user = await account();
      if (cancelled()) {
        _credentials = null;
        throw PublishCancelled();
      }
      await store.write(_credentials!.encode());
      return user;
    }
    throw const PublishingException('授权码已过期，请重新连接。');
  }

  Future<void> disconnect() async {
    await store.delete();
    _credentials = null;
  }
}
