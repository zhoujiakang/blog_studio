import 'package:blog_studio/models/markdown_path.dart';
import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/services/blog_layout_service.dart';
import 'package:blog_studio/services/publishing/public_images.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/models/publishing.dart';
import 'package:blog_studio/services/preview_manager.dart';
import 'package:blog_studio/services/managed_runtime.dart';
import 'package:blog_studio/storage/path_guard.dart';

class WebsiteArtifact {
  WebsiteArtifact(this.directory, this.files, {this.verify});
  final Future<void> Function()? verify;
  Future<void> verifyUnchanged() async => await verify?.call();
  final Directory directory;
  final Map<String, List<int>> files;
  Future<void> dispose() => directory.delete(recursive: true);
}

class BlogBuilder {
  BlogBuilder(this.environment);
  final PreviewManager environment;
  Process? _process;
  bool _cancelled = false;
  Future<void> cancel() async {
    _cancelled = true;
    await environment.cancelPreparation();
    final child = _process;
    if (child == null) return;
    try {
      child.stdin.writeln('cancel');
      await child.stdin.flush();
      await child.exitCode.timeout(const Duration(seconds: 15));
    } catch (_) {
      environment.runtimeDetector.processes.terminate(child, force: true);
    }
  }

  void _check() {
    if (_cancelled) throw PublishCancelled();
  }

  Future<WebsiteArtifact> build(
    ProjectSession project, {
    required void Function(String) progress,
  }) async {
    _cancelled = false;
    final output = await Directory.systemTemp.createTemp('inkjian-publish-');
    void changed() => progress(environment.preparationMessage);
    environment.addListener(changed);
    try {
      _check();
      final fingerprint = await inputFingerprint(project.root);
      final runtime = await environment.prepareForBuild(
        project,
        cancelled: () => _cancelled,
      );
      _check();
      progress('正在构建当前主题的网页…');
      final scripts = await environment.scripts();
      _check();
      final child = await environment.runtimeDetector.processes.start(
        runtime.nodePath!,
        [
          p.join(scripts.path, 'build.mjs'),
          project.root,
          runtime.npmPath!,
          output.path,
        ],
        environment: environment.runtimeDetector.subprocessEnvironment(
          runtime.nodePath!,
        ),
        includeParentEnvironment: false,
      );
      _process = child;
      if (_cancelled) child.stdin.writeln('cancel');
      var done = false;
      String? failure;
      final events = child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
            try {
              final event = jsonDecode(line) as Map;
              if (event['type'] == 'done') done = true;
              if (event['type'] == 'error') {
                failure = event['message'] as String?;
              }
            } catch (_) {
              failure = '构建返回的数据无法识别。';
            }
          });
      final errors = child.stderr.drain<void>();
      final code = await child.exitCode.timeout(
        const Duration(minutes: 10),
        onTimeout: () {
          unawaited(cancel());
          throw const PublishingException('构建时间过长，请检查模板后重试。');
        },
      );
      await events;
      await errors;
      _process = null;
      _check();
      if (code != 0 || !done) {
        throw PublishingException(failure ?? '博客构建失败，请检查模板后重试。');
      }
      final files = await collect(output);
      final publicImages = await PublicImages.referenced(project.root);
      files.removeWhere(
        (name, _) =>
            name.startsWith('img/') &&
            !publicImages.contains(name.substring(4)),
      );
      _check();
      Future<void> verify() async {
        if (await inputFingerprint(project.root) != fingerprint) {
          throw const PublishingException('构建期间博客内容或模板发生了外部修改，未上传。请重新发布。');
        }
      }

      await verify();
      return WebsiteArtifact(output, files, verify: verify);
    } catch (e) {
      if (_process != null) await cancel();
      if (await output.exists()) await output.delete(recursive: true);
      if (e is PreviewPreparationCancelled) throw PublishCancelled();
      rethrow;
    } finally {
      _process = null;
      environment.removeListener(changed);
    }
  }

  static Future<String> inputFingerprint(String root) async {
    final store = FileStore(PathGuard(root));
    final template = await BlogLayoutService(root).activeTemplate();
    final canonical = await Directory(root).resolveSymbolicLinks();
    final hashes = <String, String>{
      'blog.json': contentHash(await store.read('blog.json')),
    };
    Future<void> scan(Directory directory, {required bool posts}) async {
      if (!await directory.exists()) return;
      await for (final entity in directory.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (name.startsWith('.') ||
            ['node_modules', 'dist', 'build'].contains(name)) {
          continue;
        }
        if (entity is Directory) {
          await scan(entity, posts: posts);
        } else if (entity is File && (!posts || isMarkdownPath(name))) {
          final relative = p
              .relative(entity.path, from: canonical)
              .split(p.separator)
              .join('/');
          hashes[relative] = contentHash(await store.read(relative));
        }
      }
    }

    await scan(
      Directory(await store.guard.resolve('resource/posts')),
      posts: true,
    );
    await scan(
      Directory(await store.guard.resolve('template/$template')),
      posts: false,
    );
    final about = File(await store.guard.resolve('resource/about.md'));
    if (await about.exists()) {
      hashes['resource/about.md'] = contentHash(await about.readAsBytes());
    }
    for (final image in await PublicImages.referenced(root)) {
      final relative = 'resource/images/$image';
      final file = File(await store.guard.resolve(relative));
      if (await file.exists()) {
        hashes[relative] = contentHash(await file.readAsBytes());
      }
    }
    final names = hashes.keys.toList()..sort();
    return contentHash(
      utf8.encode(jsonEncode({for (final name in names) name: hashes[name]})),
    );
  }

  static Future<Map<String, List<int>>> collect(Directory output) async {
    final guard = PathGuard(output.path);
    final files = <String, List<int>>{};
    var size = 0;
    await for (final entity in output.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is Link) throw const PublishingException('构建产物含符号链接，未上传。');
      if (entity is! File) continue;
      final name = p
          .relative(entity.path, from: output.path)
          .split(p.separator)
          .join('/');
      if (name
              .split('/')
              .any(
                (part) =>
                    part.startsWith('.') ||
                    [
                      'resource',
                      'template',
                      'node_modules',
                      'source',
                    ].contains(part),
              ) ||
          [
            'blog.json',
            'template.json',
            'package.json',
            'package-lock.json',
          ].contains(p.basename(name)) ||
          isMarkdownPath(name) ||
          name.endsWith('.map')) {
        throw const PublishingException('构建产物含源码、私有目录或配置文件，未上传。请检查模板。');
      }
      final file = File(await guard.resolve(name));
      final length = await file.length();
      size += length;
      if (length > 40 * 1024 * 1024 ||
          size > 100 * 1024 * 1024 ||
          files.length >= 3000) {
        throw const PublishingException('网站文件过多或过大，请压缩图片后重试。');
      }
      files[name] = await file.readAsBytes();
    }
    if (!files.containsKey('index.html')) {
      throw const PublishingException('模板没有生成网页入口，未上传。');
    }
    return files;
  }
}
