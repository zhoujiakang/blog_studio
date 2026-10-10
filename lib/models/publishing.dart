import 'dart:convert';

class PublishingException implements Exception {
  const PublishingException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PublishCancelled implements Exception {}

class PublishTarget {
  PublishTarget(this.owner, this.repository) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]*$').hasMatch(owner) ||
        !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(repository) ||
        repository == '.' ||
        repository == '..') {
      throw const PublishingException('仓库名称无效，请重新选择。');
    }
  }
  factory PublishTarget.fromJson(Map<String, dynamic> value) =>
      PublishTarget(value['owner'] as String, value['repository'] as String);
  final String owner, repository;
  String get fullName => '$owner/$repository';
  String get apiPath => '/repos/$owner/$repository';
  Uri get website => Uri.https(
    '$owner.github.io',
    repository.toLowerCase() == '$owner.github.io'.toLowerCase()
        ? '/'
        : '/$repository/',
  );
  Map<String, dynamic> toJson() => {
    'provider': 'github-pages',
    'owner': owner,
    'repository': repository,
  };
}

class GitHubAccount {
  const GitHubAccount(this.login);
  final String login;
}

class GitHubRepository {
  GitHubRepository.fromJson(Map<String, dynamic> value)
    : target = PublishTarget(
        value['owner']['login'] as String,
        value['name'] as String,
      ),
      private = value['private'] == true,
      administrator = value['permissions']?['admin'] == true,
      archived = value['archived'] == true,
      size = value['size'] as int? ?? 0,
      branch = value['default_branch'] as String? ?? 'main';
  final PublishTarget target;
  final bool private, administrator, archived;
  final String branch;
  final int size;
}

class DeviceAuthorization {
  const DeviceAuthorization({
    required this.code,
    required this.userCode,
    required this.expiresAt,
    required this.interval,
  });
  final String code, userCode;
  final DateTime expiresAt;
  final Duration interval;
  Uri get verificationUri => Uri.https('github.com', '/login/device');
}

class GitHubCredentials {
  const GitHubCredentials(this.token, this.expiresAt);
  factory GitHubCredentials.decode(String raw) {
    final value = jsonDecode(raw) as Map;
    return GitHubCredentials(
      value['token'] as String,
      value['expiresAt'] == null ? null : DateTime.parse(value['expiresAt']),
    );
  }
  final String token;
  final DateTime? expiresAt;
  bool get expired =>
      expiresAt != null &&
      DateTime.now().add(const Duration(minutes: 1)).isAfter(expiresAt!);
  String encode() =>
      jsonEncode({'token': token, 'expiresAt': expiresAt?.toIso8601String()});
}

class PublishedVersion {
  const PublishedVersion(this.commit, this.url, this.time);
  final String commit;
  final Uri url;
  final DateTime time;
}
