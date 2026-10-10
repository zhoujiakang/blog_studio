import 'package:pub_semver/pub_semver.dart';
import 'package:blog_studio/app/app_version.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blog_studio/models/studio_exception.dart';
import 'package:blog_studio/storage/file_store.dart';

typedef TemplateDownload = Future<Uint8List> Function(Uri uri, int maxBytes);

/// Downloads public files from main and verifies one complete catalog before installation.
class GitHubTemplateSource {
  GitHubTemplateSource({TemplateDownload? download})
    : _download = download ?? _httpDownload;

  static final shared = GitHubTemplateSource();
  static const repository = 'zhoujiakang/blog_studio';
  static const catalogBranch = 'main';
  static const protocolVersion = 2;
  static const manifestPath = 'assets/generated/template-manifest.json';
  final TemplateDownload _download;
  final _files = <String, Map<String, dynamic>>{};
  final _bytes = <String, Uint8List>{};
  Future<Uint8List>? _catalog;
  String _cacheKey = '';

  Uri _fileUri(String path) => Uri.https(
    'raw.githubusercontent.com',
    '/$repository/$catalogBranch/$path',
    {'inkjian': _cacheKey},
  );

  Future<Uint8List> read(String path) async {
    if (path == manifestPath) {
      return _catalog ??= _loadCatalog().catchError((Object error) {
        _catalog = null; // A failed request can be retried without restarting.
        throw error;
      });
    }
    await read(manifestPath);
    final record = _files[path];
    if (record == null) throw const FormatException('模板文件不在下载清单中。');
    if (_bytes[path] case final cached?) return cached;
    final bytes = await _download(_fileUri(path), record['length'] as int);
    if (bytes.length != record['length'] ||
        contentHash(bytes) != record['hash']) {
      throw const _TemplateChanged('模板下载内容与清单不一致。');
    }
    return _bytes[path] = bytes;
  }

  Future<void> prepare(String id) async {
    // Retry the complete selection once if main changed during download.
    for (var attempt = 0; attempt < 2; attempt++) {
      await read(manifestPath);
      final paths = _files.keys
          .where((p) => p.startsWith('template/$id/'))
          .toList();
      if (paths.isEmpty) throw const FormatException('所选模板已不可用，请重新选择。');
      try {
        for (var offset = 0; offset < paths.length; offset += 4) {
          // Wait for every request before resetting the catalog/cache.
          await Future.wait(paths.skip(offset).take(4).map(read));
        }
        return;
      } on _TemplateChanged {
        _catalog = null;
        _files.clear();
        _bytes.clear();
        if (attempt == 1) {
          throw const FormatException('模板下载内容与清单不一致，未安装任何文件，请稍后重试。');
        }
      }
    }
  }

  Future<Uint8List> _loadCatalog() async {
    _cacheKey = DateTime.now().microsecondsSinceEpoch.toString();
    final bytes = await _download(_fileUri(manifestPath), 2 * 1024 * 1024);
    final doc = jsonDecode(utf8.decode(bytes)) as Map;
    if (doc['version'] != '2' || doc['templates'] is! List) {
      throw const FormatException('GitHub 模板清单版本不支持。');
    }
    final records = <String, Map<String, dynamic>>{};
    final compatible = <Map>[];
    final appVersion = Version.parse(AppVersion.version);
    var total = 0;
    for (final template in doc['templates'] as List) {
      final id = template['id'];
      if (id is! String ||
          !RegExp(r'^[a-zA-Z0-9\u4e00-\u9fff][a-zA-Z0-9_\u4e00-\u9fff-]*$')
              .hasMatch(id)) {
        throw const FormatException('GitHub 模板名称无效。');
      }
      final protocol = template['protocolVersion'];
      final minimum = template['minAppVersion'];
      if (protocol is! int || minimum is! String) {
        throw const FormatException('模板兼容信息无效。');
      }
      final minimumVersion = Version.parse(minimum);
      if (protocol != protocolVersion || appVersion < minimumVersion) continue;
      compatible.add(template as Map);
      for (final item in template['files'] as List) {
        final record = Map<String, dynamic>.from(item as Map);
        final path = record['path'];
        final length = record['length'];
        final hash = record['hash'];
        if (path is! String ||
            path.contains('\\') ||
            path.split('/').any((p) => p.isEmpty || p == '.' || p == '..') ||
            length is! int ||
            length < 0 ||
            length > 20 * 1024 * 1024 ||
            hash is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
          throw const FormatException('GitHub 模板文件清单无效。');
        }
        final key = 'template/$id/$path';
        if (records.containsKey(key)) throw const FormatException('模板文件重复。');
        records[key] = record;
        total += length;
        if (total > 100 * 1024 * 1024 || records.length > 10000) {
          throw const FormatException('模板下载清单过大。');
        }
      }
    }
    if (compatible.isEmpty) {
      throw const FormatException('暂时没有适合当前应用的模板，请更新应用后重试。');
    }
    _files
      ..clear()
      ..addAll(records);
    return Uint8List.fromList(
      utf8.encode(jsonEncode({...doc, 'templates': compatible})),
    );
  }

  static Future<Uint8List> _httpDownload(Uri uri, int maxBytes) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      return await (() async {
        final request = await client.getUrl(uri);
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'InkJian/${AppVersion.version}',
        );
        request.headers.set(HttpHeaders.acceptHeader, '*/*');
        request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
        final response = await request.close();
        if (response.statusCode == HttpStatus.notFound) {
          throw const _TemplateChanged('模板下载文件不存在，请稍后重试或反馈。');
        }
        if (response.statusCode != HttpStatus.ok) {
          throw StudioException(
            StudioError.invalidProject,
            switch (response.statusCode) {
              403 => '模板下载被拒绝，请检查网络后重试。',
              429 => '模板下载请求过于频繁，请稍后重试。',
              _ => '模板下载失败（${response.statusCode}），请稍后重试。',
            },
          );
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (builder.length + chunk.length > maxBytes) {
            throw const _TemplateChanged('模板文件超过清单大小。');
          }
          builder.add(chunk);
        }
        return builder.takeBytes();
      })().timeout(const Duration(seconds: 45));
    } on SocketException {
      throw const StudioException(
        StudioError.invalidProject,
        '无法连接模板服务，请检查网络后重试。',
      );
    } on TimeoutException {
      throw const StudioException(StudioError.invalidProject, '模板下载超时，请重新尝试。');
    } finally {
      client.close(force: true);
    }
  }
}

class _TemplateChanged extends FormatException {
  const _TemplateChanged(super.message);
}
