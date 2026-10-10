import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:blog_studio/models/publishing.dart';
import 'package:blog_studio/services/publishing/github_auth.dart';
import 'package:blog_studio/services/publishing/github_transport.dart';

class RemoteWebsite {
  const RemoteWebsite(this.head, this.files);
  final String? head;
  final Map<String, String> files;
}

class GitHubPages {
  GitHubPages(this.auth, {GitHubTransport? transport})
    : transport = transport ?? auth.transport;
  final GitHubAuth auth;
  final GitHubTransport transport;
  Future<dynamic> _request(String method, String path, [Object? body]) async =>
      transport.request(
        method,
        Uri.https('api.github.com', path),
        token: await auth.token(),
        body: body,
      );
  Future<List<dynamic>> _pages(String path, String key) async {
    final result = <dynamic>[];
    for (var page = 1; page <= 100; page++) {
      final response = await transport.request(
        'GET',
        Uri.https('api.github.com', path, {'per_page': '100', 'page': '$page'}),
        token: await auth.token(),
      );
      final items = response[key] as List;
      result.addAll(items);
      if (items.length < 100) return result;
    }
    throw const PublishingException('授权数据过多，请减少应用授权的仓库后重试。');
  }

  Future<List<GitHubRepository>> repositories() async {
    // Public repositories can be readable without an installation. Only offer
    // repositories explicitly granted to this app, never all /user/repos.
    final installations = await _pages('/user/installations', 'installations');
    final account = await auth.account();
    final result = <GitHubRepository>[];
    for (final installation in installations) {
      if (installation['app_slug'] != auth.settings.slug ||
          installation['account']?['login'].toString().toLowerCase() !=
              account.login.toLowerCase()) {
        continue;
      }
      if (installation['suspended_at'] != null) {
        throw const PublishingException(
          'InkJian 的仓库授权已暂停，请在 GitHub 应用安装设置中恢复。',
        );
      }
      final permissions = installation['permissions'] as Map? ?? {};
      final missing = [
        for (final name in ['contents', 'pages', 'administration'])
          if (permissions[name] != 'write') name,
      ];
      if (missing.isNotEmpty) {
        throw PublishingException(
          '当前安装授权尚未包含 ${missing.join('、')} 写入权限。请在 GitHub 已安装应用中接受新权限，再刷新仓库。',
        );
      }
      final items = await _pages(
        '/user/installations/${installation['id']}/repositories',
        'repositories',
      );
      result.addAll(
        items
            .map((e) => GitHubRepository.fromJson(Map<String, dynamic>.from(e)))
            .where(
              (r) =>
                  !r.private &&
                  r.administrator &&
                  !r.archived &&
                  r.target.owner.toLowerCase() == account.login.toLowerCase(),
            ),
      );
    }
    return result;
  }

  Future<RemoteWebsite> inspect(
    PublishTarget target,
    String workspaceId, {
    String? expectedHead,
  }) async {
    final repository = GitHubRepository.fromJson(
      Map<String, dynamic>.from(await _request('GET', target.apiPath)),
    );
    if (repository.private ||
        !repository.administrator ||
        repository.archived ||
        repository.branch != 'main') {
      throw const PublishingException('请选择自己可管理、以 main 为默认分支的公开仓库。');
    }
    String head;
    try {
      final reference = await _request(
        'GET',
        '${target.apiPath}/git/ref/heads/main',
      );
      head = reference['object']['sha'] as String;
    } on GitHubFailure catch (e) {
      if (e.status != 404 && e.status != 409) rethrow;
      // Only a truly empty repository may start without a main reference.
      dynamic refs;
      try {
        refs = await _request(
          'GET',
          '${target.apiPath}/git/matching-refs/heads/',
        );
      } on GitHubFailure catch (missing) {
        if ((missing.status != 409 && missing.status != 404) ||
            repository.size != 0) {
          rethrow;
        }
        refs = <dynamic>[];
      }
      if ((refs as List).isNotEmpty) {
        throw const PublishingException('仓库已有其他分支，请选择空仓库。');
      }
      if (expectedHead != null) {
        throw const PublishingException('远程发布记录已被删除，请检查仓库后重新关联。');
      }
      if (repository.size != 0) {
        throw const PublishingException('仓库含其他历史内容，请选择新建的空仓库。');
      }
      return const RemoteWebsite(null, {});
    }
    if (expectedHead != null && head != expectedHead) {
      throw const PublishingException('发布仓库已被其他操作修改，应用未覆盖远程内容。请检查仓库后重试。');
    }
    final commit = await _request('GET', '${target.apiPath}/git/commits/$head');
    final tree = await transport.request(
      'GET',
      Uri.https(
        'api.github.com',
        '${target.apiPath}/git/trees/${commit['tree']['sha']}',
        {'recursive': '1'},
      ),
      token: await auth.token(),
    );
    if (tree['truncated'] == true) {
      throw const PublishingException('仓库文件过多，不适合直接关联为发布仓库。');
    }
    final entries = tree['tree'] as List;
    if (entries.any(
      (e) =>
          e['type'] != 'tree' && (e['type'] != 'blob' || e['mode'] != '100644'),
    )) {
      throw const PublishingException('仓库含特殊文件，请选择空的发布仓库。');
    }
    final files = <String, String>{
      for (final entry in entries.where((e) => e['type'] == 'blob'))
        entry['path'] as String: entry['sha'] as String,
    };
    final markerSha = files['.inkjian-site.json'];
    if (markerSha == null) {
      if (files.keys.any((name) => name != 'README.md')) {
        throw const PublishingException(
          '这个仓库已有其他内容。请选择空仓库或仅含 README 的新仓库，原有文件不会被覆盖。',
        );
      }
    } else {
      final blob = await _request(
        'GET',
        '${target.apiPath}/git/blobs/$markerSha',
      );
      if (blob['encoding'] != 'base64') {
        throw const PublishingException('仓库发布标记无法识别。');
      }
      final marker = jsonDecode(
        utf8.decode(
          base64Decode((blob['content'] as String).replaceAll('\n', '')),
        ),
      );
      if (marker['formatVersion'] != 1 ||
          marker['workspaceId'] != workspaceId) {
        throw const PublishingException('这个仓库属于另一个博客，请选择其他发布仓库。');
      }
      final managed = marker['files'];
      if (managed is! List ||
          files.keys.any(
            (name) => name != '.inkjian-site.json' && !managed.contains(name),
          )) {
        throw const PublishingException('发布仓库中出现了其他文件，应用未覆盖它们。请检查仓库后重试。');
      }
    }
    return RemoteWebsite(head, files);
  }

  static String blobHash(List<int> bytes) => sha1.convert([
    ...utf8.encode('blob ${bytes.length}\u0000'),
    ...bytes,
  ]).toString();
  Future<String> upload(
    PublishTarget target,
    String workspaceId,
    RemoteWebsite remote,
    Map<String, List<int>> input, {
    required void Function(String) progress,
    required void Function() check,
  }) async {
    if (remote.head == null) {
      check();
      // Git Data APIs cannot create refs in an empty Git repository. Bootstrap
      // with the Contents API; Pages is still disabled and no website is exposed.
      final seed = utf8.encode(
        jsonEncode({
          'formatVersion': 1,
          'workspaceId': workspaceId,
          'files': <String>[],
        }),
      );
      progress('正在初始化发布仓库…');
      final initialized = await _request(
        'PUT',
        '${target.apiPath}/contents/.inkjian-site.json',
        {
          'message': 'Initialize InkJian website',
          'content': base64Encode(seed),
        },
      );
      check();
      remote = await inspect(
        target,
        workspaceId,
        expectedHead: initialized['commit']['sha'] as String,
      );
    }
    final files = {
      ...input,
      '.nojekyll': <int>[],
      '.inkjian-site.json': utf8.encode(
        jsonEncode({
          'formatVersion': 1,
          'workspaceId': workspaceId,
          'files': [...input.keys, '.nojekyll'],
        }),
      ),
    };
    final tree = <Map<String, dynamic>>[];
    var uploaded = 0;
    for (final entry in files.entries) {
      check();
      final localSha = blobHash(entry.value);
      String sha;
      if (remote.files[entry.key] == localSha) {
        sha = localSha;
      } else {
        final blob = await _request('POST', '${target.apiPath}/git/blobs', {
          'content': base64Encode(entry.value),
          'encoding': 'base64',
        });
        sha = blob['sha'] as String;
        if (sha != localSha) throw const PublishingException('上传文件校验失败，未更新网站。');
      }
      tree.add({
        'path': entry.key,
        'mode': '100644',
        'type': 'blob',
        'sha': sha,
      });
      progress('正在上传网页 ${++uploaded}/${files.length}…');
    }
    check();
    final createdTree = await _request('POST', '${target.apiPath}/git/trees', {
      'tree': tree,
    });
    check();
    final commit = await _request('POST', '${target.apiPath}/git/commits', {
      'message': 'Publish website with InkJian',
      'tree': createdTree['sha'],
      'parents': [if (remote.head != null) remote.head],
    });
    check();
    // Never force-push. A concurrent remote edit is rejected by GitHub.
    if (remote.head == null) {
      await _request('POST', '${target.apiPath}/git/refs', {
        'ref': 'refs/heads/main',
        'sha': commit['sha'],
      });
    } else {
      await _request('PATCH', '${target.apiPath}/git/refs/heads/main', {
        'sha': commit['sha'],
        'force': false,
      });
    }
    return commit['sha'] as String;
  }

  Future<Uri> enable(PublishTarget target) async {
    dynamic site;
    try {
      site = await _request('GET', '${target.apiPath}/pages');
    } on GitHubFailure catch (e) {
      if (e.status != 404) rethrow;
      site = await _request('POST', '${target.apiPath}/pages', {
        'build_type': 'legacy',
        'source': {'branch': 'main', 'path': '/'},
      });
    }
    if (site['build_type'] == 'workflow' ||
        site['source']?['branch'] != 'main' ||
        site['source']?['path'] != '/') {
      throw const PublishingException(
        '这个仓库使用其他发布方式，请在 GitHub 中确认 Pages 来源为 main 分支根目录，再重试。',
      );
    }
    final url = Uri.tryParse(site['html_url'] as String? ?? '');
    if (url == null || url.scheme != 'https' || url.host.isEmpty) {
      throw const PublishingException('GitHub 尚未返回网站地址，请稍后重试。');
    }
    return url;
  }

  Future<bool> isBuilt(PublishTarget target, String commit) async {
    dynamic builds;
    try {
      builds = await _request('GET', '${target.apiPath}/pages/builds');
    } on GitHubFailure catch (e) {
      if (e.status == 404) return false;
      rethrow;
    }
    for (final build in builds as List) {
      if (build['commit'] != commit) continue;
      if (build['status'] == 'errored') {
        throw const PublishingException('GitHub 未能完成网站上线，请稍后重试或检查 Pages 状态。');
      }
      if (build['status'] == 'built') return true;
    }
    return false;
  }
}
