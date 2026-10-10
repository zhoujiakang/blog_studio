import 'dart:convert';
import 'dart:io';

import 'package:blog_studio/storage/resource_layout.dart';

import 'dart:typed_data';

import 'package:blog_studio/services/github_template_source.dart';
import 'package:path/path.dart' as p;

import 'package:blog_studio/models/studio_exception.dart';
import 'package:blog_studio/models/blog_template.dart';
import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/storage/path_guard.dart';

typedef AssetReader = Future<Uint8List> Function(String path);

class TemplateInstaller {
  TemplateInstaller({AssetReader? readAsset, GitHubTemplateSource? source})
    : _remote = readAsset == null
          ? source ?? GitHubTemplateSource.shared
          : null {
    this.readAsset = readAsset ?? _remote!.read;
  }
  final GitHubTemplateSource? _remote;
  late final AssetReader readAsset;
  static bool _installable(String path) =>
      path != '.gitignore' &&
      path != 'README.md' &&
      !path.startsWith('tests/') &&
      path != 'vitest.config.ts';

  Future<List<BlogTemplate>> listTemplates() async {
    final manifest = jsonDecode(
      utf8.decode(await readAsset('assets/generated/template-manifest.json')),
    ) as Map;
    if (manifest['version'] != '2') {
      throw const FormatException('模板清单版本不支持，请重新生成模板资源。');
    }
    final ids = <String>{};
    final templates = <BlogTemplate>[];
    for (final entry in manifest['templates'] as List) {
      final id = entry['id'] as String;
      if (!RegExp(r'^[a-zA-Z0-9\u4e00-\u9fff][a-zA-Z0-9_\u4e00-\u9fff-]*$')
              .hasMatch(id) ||
          id.startsWith('.') ||
          id.contains(RegExp(r'[/\\]')) ||
          !ids.add(id)) {
        throw const FormatException('模板风格名称无效或重复。');
      }
      final files = (entry['files'] as List)
          .map((file) => Map<String, dynamic>.from(file as Map))
          .toList();
      if (files.isEmpty) throw const FormatException('模板没有可安装的文件。');
      for (final file in files) {
        final path = file['path'] as String;
        if (path == 'resource' ||
            path.startsWith('resource/') ||
            path
                .split('/')
                .any(
                  (part) => ['node_modules', 'dist', 'build'].contains(part),
                )) {
          throw const FormatException('模板只能包含网站源码，不能包含用户资源、依赖或构建产物。');
        }
      }
      templates.add(
        BlogTemplate(id: id, name: entry['name'] as String, files: files),
      );
    }
    if (templates.isEmpty) throw const FormatException('暂时没有可用的博客模板。');
    return templates;
  }

  Future<BlogTemplate> _prepareTemplate(BlogTemplate selected) async {
    if (_remote == null) return selected;
    await _remote.prepare(selected.id);
    // A retry may have loaded new file hashes, lengths or added/removed files.
    final current = (await listTemplates())
        .where((t) => t.id == selected.id)
        .firstOrNull;
    if (current == null) throw const FormatException('所选模板已不可用，请重新选择。');
    return current;
  }

  Future<void> installStyle(String root, String id) async {
    final selected = (await listTemplates())
        .where((t) => t.id == id)
        .firstOrNull;
    if (selected == null) throw const FormatException('所选模板不存在');
    final store = FileStore(PathGuard(root));
    final layout = ResourceLayout(root);
    final dir = Directory(
      await store.guard.resolve('${layout.templateDirectory}/$id'),
    );
    if (await dir.exists()) throw const FormatException('模板目录已存在，不覆盖其配置。');
    final prepared = await _prepareTemplate(selected);
    final staged = <String, Uint8List>{};
    for (final record in prepared.files) {
      final path = record['path'] as String;
      if (!_installable(path)) continue;
      final target = '${layout.templateDirectory}/$id/$path';
      await store.guard.resolve(target);
      var bytes = await readAsset('template/$id/$path');
      if (bytes.length != record['length'] ||
          contentHash(bytes) != record['hash']) {
        throw const FormatException('模板校验失败');
      }
      if (path == 'template.json') {
        final config = Map<String, dynamic>.from(
          jsonDecode(utf8.decode(bytes)) as Map,
        );
        config.remove('site');
        bytes = Uint8List.fromList(
          utf8.encode(
            '${const JsonEncoder.withIndent('  ').convert(config)}\n',
          ),
        );
      }
      staged[target] = bytes;
    }
    final created = <String, String>{};
    final createdDirs = <String>{};
    try {
      for (final entry in staged.entries) {
        final path = entry.key;
        var parent = File(await store.guard.resolve(path)).parent;
        while (p.isWithin(root, parent.path) && !await parent.exists()) {
          createdDirs.add(parent.path);
          parent = parent.parent;
        }
        created[path] = await store.write(
          path,
          entry.value,
          expectedHash: null,
        );
      }
    } catch (_) {
      for (final entry in created.entries) {
        final file = File(await store.guard.resolve(entry.key));
        if (await file.exists() &&
            contentHash(await file.readAsBytes()) == entry.value) {
          await file.delete();
        }
      }
      final dirs = createdDirs.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final path in dirs) {
        final directory = Directory(path);
        if (await directory.exists() &&
            (await directory.list().toList()).isEmpty) {
          await directory.delete();
        }
      }
      rethrow;
    }
  }

  Future<void> initialize(String root, {String? templateId}) async {
    final target = Directory(root);
    if ((await target.list().toList()).isNotEmpty) {
      throw const StudioException(
        StudioError.nonEmptyDirectory,
        '仅能在空目录创建博客，已有文件不会被覆盖。',
      );
    }
    final templates = await listTemplates();
    final selected = templateId == null
        ? templates.first
        : templates.where((template) => template.id == templateId).firstOrNull;
    if (selected == null) {
      throw const StudioException(StudioError.invalidProject, '所选博客模板不存在。');
    }
    final prepared = await _prepareTemplate(selected);
    final stage = await Directory.systemTemp.createTemp(
      'blog-studio-template-',
    );
    final created = <String, String>{};
    final createdDirs = <String>{};
    final guard = PathGuard(root);
    try {
      for (final record in prepared.files) {
        final relative = record['path'] as String;
        // Validate before using the manifest's paths in staging or the target.
        await guard.resolve(relative);
        final bytes = await readAsset('template/${selected.id}/$relative');
        if (bytes.length != record['length'] ||
            contentHash(bytes) != record['hash']) {
          throw const StudioException(
            StudioError.invalidProject,
            '模板校验失败，请重新尝试。',
          );
        }
        final file = File(p.join(stage.path, relative));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
      }
      if ((await target.list().toList()).isNotEmpty) {
        throw const StudioException(
          StudioError.nonEmptyDirectory,
          '目标目录新增了文件，创建已取消。',
        );
      }
      final output = <String, Uint8List>{};
      for (final record in prepared.files) {
        final relative = record['path'] as String;
        final bytes = await File(p.join(stage.path, relative)).readAsBytes();
        if (_installable(relative)) {
          output['template/${selected.id}/$relative'] = bytes;
        }
      }
      final config = jsonDecode(
        await File(p.join(stage.path, 'template.json')).readAsString(),
      ) as Map<String, dynamic>;
      final site = Map<String, dynamic>.from(
        config.remove('site') as Map? ?? {},
      );
      output['template/${selected.id}/template.json'] = Uint8List.fromList(
        utf8.encode('${const JsonEncoder.withIndent('  ').convert(config)}\n'),
      );
      output['blog.json'] = Uint8List.fromList(
        utf8.encode(
          '${const JsonEncoder.withIndent('  ').convert({'formatVersion': 2, 'activeTemplate': selected.id, 'site': site})}\n',
        ),
      );
      output.putIfAbsent(
        'resource/about.md',
        () => Uint8List.fromList(utf8.encode('# 关于\n')),
      );
      for (final entry in output.entries) {
        final file = File(await guard.resolve(entry.key));
        var parent = file.parent;
        while (p.isWithin(root, parent.path) && !await parent.exists()) {
          createdDirs.add(parent.path);
          parent = parent.parent;
        }
        await file.parent.create(recursive: true);
        await file.create(exclusive: true);
        created[entry.key] = contentHash(const []);
        await file.writeAsBytes(entry.value, flush: true);
        created[entry.key] = contentHash(entry.value);
      }
      for (final name in ['posts', 'drafts', 'notes', 'images']) {
        final dir = Directory(await guard.resolve('resource/$name'));
        if (!await dir.exists()) {
          createdDirs.add(dir.path);
          await dir.create(recursive: true);
        }
      }
    } catch (_) {
      for (final entry in created.entries) {
        final file = File(await guard.resolve(entry.key));
        if (await file.exists() &&
            contentHash(await file.readAsBytes()) == entry.value) {
          await file.delete();
        }
      }
      final dirs = createdDirs.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final path in dirs) {
        final dir = Directory(path);
        if (await dir.exists() && (await dir.list().toList()).isEmpty) {
          await dir.delete();
        }
      }
      rethrow;
    } finally {
      await stage.delete(recursive: true);
    }
  }
}
