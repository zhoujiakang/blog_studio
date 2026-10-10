import 'package:blog_studio/storage/resource_layout.dart';
import 'package:blog_studio/platform/runtime_dependencies.dart';
import 'package:blog_studio/platform/contracts/runtime_platform.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/models/runtime_environment.dart';
import 'package:blog_studio/services/runtime_detector.dart';

typedef RuntimeProgress = void Function(String message, double? fraction);
typedef RuntimeFetcher = Future<void> Function(
  Uri url,
  File target,
  int limit,
  void Function(int, int?) progress,
);

class PreviewPreparationCancelled implements Exception {}

/// Downloads the official portable runtime into the app's own support folder.
/// Never modifies a system installation, shell profile, or the user's blog files.
class ManagedRuntime {
  ManagedRuntime({
    Directory? directory,
    this.fetcher,
    this.architecture,
    RuntimePlatform? platform,
    ProcessRunner? processes,
  }) : platform = platform ?? RuntimeDependencies.platform,
       processes = processes ?? RuntimeDependencies.processes,
       directory =
           directory ??
           (platform ?? RuntimeDependencies.platform).runtimeDirectory;
  final RuntimePlatform platform;
  final ProcessRunner processes;
  final Directory directory;
  final RuntimeFetcher? fetcher;
  final Future<String> Function()? architecture;
  HttpClient? _client;
  Process? _tar;
  bool _cancelled = false;
  bool _installing = false;
  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
    if (_tar != null) processes.terminate(_tar!);
  }

  void _check() {
    if (_cancelled) throw PreviewPreparationCancelled();
  }

  Future<RuntimeEnvironment?> detect(
    ProjectSession project,
    RuntimeDetector detector,
  ) async {
    if (!await directory.exists()) return null;
    final candidates = await directory
        .list(followLinks: false)
        .where(
          (e) => e is Directory && platform.isRuntimeFolder(p.basename(e.path)),
        )
        .cast<Directory>()
        .toList();
    candidates.sort((a, b) => b.path.compareTo(a.path));
    for (final folder in candidates) {
      try {
        final marker = jsonDecode(
          await File(p.join(folder.path, 'runtime.json')).readAsString(),
        ) as Map;
        if (marker['source'] != 'https://nodejs.org/dist/' ||
            marker['formatVersion'] != 1) {
          continue;
        }
        final result = await detector.detect(
          project,
          nodePath: platform.nodePath(folder.path),
          npmPath: platform.npmPath(folder.path),
        );
        if (result.status == RuntimeStatus.ready) return result;
      } catch (_) {
        /* A broken cached version does not prevent a fresh download. */
      }
    }
    return null;
  }

  static String selectRelease(
    List<dynamic> releases,
    String requirement,
    String arch, {
    String? releaseFile,
  }) {
    final constraint = VersionConstraint.parse(requirement);
    final compatible = releases.whereType<Map>().where((release) {
      final v = release['version'];
      return v is String &&
          RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(v) &&
          release['lts'] is String &&
          (release['files'] as List? ?? []).contains(
            releaseFile ?? 'osx-$arch-tar',
          ) &&
          constraint.allows(Version.parse(v.substring(1)));
    }).toList();
    compatible.sort(
      (a, b) =>
          Version.parse(b['version'].substring(1))
              .compareTo(Version.parse(a['version'].substring(1))),
    );
    // Prefer the established LTS line used by our template; other constraints
    // may request a newer LTS. Never download an incompatible/current release.
    final preferred = compatible
        .where((release) => release['version'].startsWith('v22.'))
        .firstOrNull;
    if (preferred != null) return preferred['version'] as String;
    if (compatible.isEmpty) throw const FormatException('暂时没有适合这个博客的预览组件。');
    return compatible.first['version'] as String;
  }

  static String checksum(String sums, String filename) {
    final matches = sums
        .split('\n')
        .map(
          (line) =>
              RegExp(r'^([a-fA-F0-9]{64})\s+\*?(.+)$').firstMatch(line.trim()),
        )
        .whereType<RegExpMatch>()
        .where((m) => m.group(2) == filename)
        .toList();
    if (matches.length != 1) throw const FormatException('下载文件的校验信息不完整。');
    return matches.single.group(1)!.toLowerCase();
  }

  static void validateArchive(String listing, String folder) {
    final entries = listing
        .split('\n')
        .where((line) => line.isNotEmpty)
        .toList();
    if (entries.isEmpty || entries.length > 30000) {
      throw const FormatException('下载文件的内容不正确。');
    }
    for (final entry in entries) {
      final parts = entry.replaceFirst(RegExp(r'/$'), '').split('/');
      if (parts.first != folder ||
          parts.any((s) => s.isEmpty || s == '.' || s == '..') ||
          entry.contains('\\')) {
        throw const FormatException('下载文件包含不安全的路径。');
      }
    }
  }

  Future<RuntimeEnvironment> install(
    ProjectSession project,
    RuntimeDetector detector,
    RuntimeProgress progress,
  ) async {
    if (_installing) throw StateError('已有准备任务正在进行');
    _installing = true;
    _cancelled = false;
    Directory? stage;
    try {
      progress('正在获取预览组件…', null);
      final arch = architecture != null
          ? await architecture!()
          : await platform.architecture();
      if (!['arm64', 'x64'].contains(arch)) {
        throw const FormatException('这台电脑暂不支持自动准备。');
      }
      final package = jsonDecode(
        await File(
          p.join(ResourceLayout(project.root).packageRoot, 'package.json'),
        ).readAsString(),
      ) as Map;
      final requirement =
          package['engines']?['node']?.toString() ?? '>=22.18.0';
      await directory.create(recursive: true);
      stage = await directory.createTemp('.preparing-');
      // Only this temporary subdirectory is removed on failure/cancellation.
      final index = File(p.join(stage.path, 'index.json'));
      await _fetch(
        Uri.parse('https://nodejs.org/dist/index.json'),
        index,
        4 * 1024 * 1024,
        (_, _) {},
      );
      _check();
      final version = selectRelease(
        jsonDecode(await index.readAsString()) as List,
        requirement,
        arch,
        releaseFile: platform.releaseFile(arch),
      );
      final folder = 'node-$version-${platform.packagePlatform}-$arch';
      final archiveName = platform.archiveName(folder);
      final sums = File(p.join(stage.path, 'SHASUMS256.txt'));
      await _fetch(
        Uri.parse('https://nodejs.org/dist/$version/SHASUMS256.txt'),
        sums,
        1024 * 1024,
        (_, _) {},
      );
      final expected = checksum(await sums.readAsString(), archiveName);
      final archive = File(p.join(stage.path, archiveName));
      await _fetch(
        Uri.parse('https://nodejs.org/dist/$version/$archiveName'),
        archive,
        200 * 1024 * 1024,
        (received, total) {
          progress(
            '正在下载预览组件 · ${(received / 1024 / 1024).toStringAsFixed(1)} MB${total == null ? '' : ' / ${(total / 1024 / 1024).toStringAsFixed(1)} MB'}',
            total == null ? null : received / total,
          );
        },
      );
      _check();
      progress('正在检查下载文件…', null);
      final actual = (await sha256.bind(archive.openRead()).first).toString();
      if (actual != expected) throw const FormatException('下载文件不完整，请重新尝试。');
      final listing = await _runArchiveTool(
        platform.archiveListingArguments(archive.path),
      );
      validateArchive(listing, folder);
      _check();
      progress('正在准备预览组件…', null);
      await _runArchiveTool(
        platform.archiveExtractionArguments(archive.path, stage.path),
      );
      final extracted = Directory(p.join(stage.path, folder));
      final extractedRoot = await extracted.resolveSymbolicLinks();
      await for (final item in extracted.list(
        recursive: true,
        followLinks: false,
      )) {
        if (item is Link &&
            !p.isWithin(extractedRoot, await item.resolveSymbolicLinks())) {
          throw const FormatException('下载文件包含不安全的链接。');
        }
      }
      _check();
      final runtime = await detector.detect(
        project,
        nodePath: platform.nodePath(extracted.path),
        npmPath: platform.npmPath(extracted.path),
      );
      if (runtime.status != RuntimeStatus.ready ||
          runtime.nodeVersion != version) {
        throw const FormatException('预览组件没有准备成功，请重新尝试。');
      }
      await File(p.join(extracted.path, 'runtime.json')).writeAsString(
        jsonEncode({
          'formatVersion': 1,
          'source': 'https://nodejs.org/dist/',
          'version': version,
          'arch': arch,
          'sha256': expected,
        }),
        flush: true,
      );
      _check();
      final target = p.join(
        directory.path,
        '$folder-${DateTime.now().microsecondsSinceEpoch}',
      );
      await extracted.rename(target);
      return RuntimeEnvironment(
        status: RuntimeStatus.ready,
        nodePath: platform.nodePath(target),
        npmPath: platform.npmPath(target),
        nodeVersion: runtime.nodeVersion,
        npmVersion: runtime.npmVersion,
      );
    } catch (_) {
      _check();
      rethrow;
    } finally {
      _client?.close(force: true);
      _client = null;
      _tar = null;
      if (stage != null && await stage.exists()) {
        await stage.delete(recursive: true);
      }
      _installing = false;
    }
  }

  Future<void> _fetch(
    Uri uri,
    File file,
    int limit,
    void Function(int, int?) progress,
  ) async {
    _check();
    if (uri.scheme != 'https' || uri.host != 'nodejs.org') {
      throw const FormatException('下载来源不正确。');
    }
    if (fetcher != null) {
      await fetcher!(uri, file, limit, progress);
      _check();
      return;
    }
    final client = _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 20));
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      throw const HttpException('无法连接下载服务，请稍后重试。');
    }
    final total = response.contentLength > 0 ? response.contentLength : null;
    if (total != null && total > limit) {
      throw const FormatException('下载文件大小不正确。');
    }
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        _check();
        received += chunk.length;
        if (received > limit) throw const FormatException('下载文件大小不正确。');
        sink.add(chunk);
        progress(received, total);
        // Back-pressure prevents the archive from accumulating in memory.
        await sink.flush();
      }
      if (total != null && total != received) {
        throw const FormatException('下载文件不完整。');
      }
    } finally {
      await sink.close();
    }
  }

  Future<String> _runArchiveTool(List<String> args) async {
    _check();
    final process = await processes.start(platform.archiveTool, args);
    _tar = process;
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.drain<void>();
    try {
      final code = await process.exitCode.timeout(const Duration(seconds: 90));
      await errors;
      _check();
      if (code != 0) throw const FormatException('预览组件解压失败，请重新尝试。');
      return await output;
    } on TimeoutException {
      processes.terminate(process, force: true);
      await process.exitCode;
      throw const FormatException('准备时间过长，请重新尝试。');
    } finally {
      if (_tar == process) _tar = null;
    }
  }
}
