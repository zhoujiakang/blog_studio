import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blog_studio/models/publishing.dart';

class GitHubFailure extends PublishingException {
  const GitHubFailure(this.status, super.message);
  final int status;

  static GitHubFailure response(
    int status,
    String method,
    Uri uri, {
    String? reason,
    String? requiredPermissions,
    bool rateLimited = false,
  }) {
    final operation = switch (uri.path) {
      final p when p == '/user/installations' => '检查应用安装授权',
      final p when p.startsWith('/user/installations/') => '读取已授权仓库',
      final p when p.endsWith('/pages/builds') => '确认网站上线',
      final p when p.endsWith('/pages') =>
        method == 'POST' ? '开启 GitHub Pages' : '读取 Pages 设置',
      final p when p.contains('/contents/') => '初始化发布仓库',
      final p when p.endsWith('/git/blobs') => '上传网页文件',
      final p when p.endsWith('/git/trees') => '创建网页文件目录',
      final p when p.endsWith('/git/commits') => '保存网站版本',
      final p when p.contains('/git/refs') => '更新网站分支',
      _ => '访问 GitHub',
    };
    final explanation = switch (status) {
      401 => '登录已失效，请重新连接账号。',
      403 when rateLimited => '请求额度暂时用完，请稍后重试。',
      403 when reason == 'Resource not accessible by integration' =>
        '当前登录凭据没有此操作的授权。请确认应用已安装到此账号、包含发布仓库，并已接受最新权限。',
      403 when reason == 'You must verify your email address.' =>
        '请先在 GitHub 验证账号邮箱，再重试。',
      403 => 'GitHub 拒绝了操作，请检查当前安装授权及仓库规则。',
      404 => '未找到仓库或尚未授权此仓库，请重新选择。',
      409 || 422 => '仓库状态已变化或操作未被接受，请刷新后重试。',
      429 => '请求过于频繁，请稍后重试。',
      _ => 'GitHub 暂时无法完成操作，请稍后重试。',
    };
    // Do not echo arbitrary response text, URLs, request bodies or credentials.
    // This header contains endpoint requirements, not permissions granted to us.
    final required = RegExp(r'(contents|pages|administration)=(read|write)')
        .allMatches(requiredPermissions ?? '')
        .map((m) => m.group(0)!)
        .toSet()
        .join('、');
    return GitHubFailure(
      status,
      '$operation失败（HTTP $status）：$explanation'
      '${status == 403 && !rateLimited && required.isNotEmpty ? ' 此接口要求：$required。' : ''}',
    );
  }
}

abstract interface class GitHubTransport {
  Future<dynamic> request(
    String method,
    Uri uri, {
    String? token,
    Object? body,
  });
}

class HttpGitHubTransport implements GitHubTransport {
  @override
  Future<dynamic> request(
    String method,
    Uri uri, {
    String? token,
    Object? body,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 30));
      request.followRedirects = false;
      request.headers.set('Accept', 'application/json');
      request.headers.set('User-Agent', 'InkJian');
      if (uri.host == 'api.github.com') {
        request.headers.set('Accept', 'application/vnd.github+json');
        request.headers.set('X-GitHub-Api-Version', '2022-11-28');
      }
      if (token != null) request.headers.set('Authorization', 'Bearer $token');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 60))) {
        bytes.addAll(chunk);
        if (bytes.length > 16 * 1024 * 1024) {
          throw const PublishingException('GitHub 返回的数据过大，请缩小网站后重试。');
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String? reason;
        try {
          final data = jsonDecode(utf8.decode(bytes));
          if (data is Map && data['message'] is String) {
            reason = data['message'];
          }
        } on FormatException {
          // A proxy may return HTML instead of a GitHub JSON response.
        }
        throw GitHubFailure.response(
          response.statusCode,
          method,
          uri,
          reason: reason,
          requiredPermissions: response.headers.value(
            'x-accepted-github-permissions',
          ),
          rateLimited: response.headers.value('x-ratelimit-remaining') == '0',
        );
      }
      return bytes.isEmpty ? null : jsonDecode(utf8.decode(bytes));
    } on SocketException {
      throw const PublishingException('无法连接 GitHub，请检查网络后重试。');
    } on TimeoutException {
      throw const PublishingException('连接 GitHub 超时，请稍后重试。');
    } on FormatException {
      throw const PublishingException('GitHub 返回的数据无法识别，请稍后重试。');
    } finally {
      client.close(force: true);
    }
  }
}
