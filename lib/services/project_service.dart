import 'dart:io';

import 'package:blog_studio/storage/resource_layout.dart';

import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/models/studio_exception.dart';
import 'package:blog_studio/storage/path_guard.dart';
import 'package:blog_studio/services/template_installer.dart';
import 'package:blog_studio/services/blog_layout_service.dart';

class ProjectService {
  ProjectService({TemplateInstaller? installer})
    : installer = installer ?? TemplateInstaller();
  final TemplateInstaller installer;
  Future<DirectoryInspection> inspect(String root) async {
    final directory = Directory(root);
    if (!await directory.exists()) {
      return const DirectoryInspection(
        DirectoryKind.incompatible,
        reason: '目录不存在。',
      );
    }
    if ((await directory.list().toList()).isEmpty) {
      return const DirectoryInspection(DirectoryKind.empty);
    }
    try {
      final guard = PathGuard(root);
      final id = await BlogLayoutService(root).activeTemplate();
      if (!await Directory(await guard.resolve('resource')).exists()) {
        throw const FormatException('缺少 resource 目录。');
      }
      for (final file in [
        'template.json',
        'src/App.vue',
        'index.html',
        'package.json',
      ]) {
        await File(
          await guard.resolve(
            '${ResourceLayout(root).templateDirectory}/$id/$file',
          ),
        ).readAsBytes();
      }
      return const DirectoryInspection(DirectoryKind.compatible);
    } catch (_) {
      return const DirectoryInspection(
        DirectoryKind.incompatible,
        reason:
            '仅支持 blog.json + resource/ + template/ 的博客目录，请选择空目录创建博客或打开当前格式的博客。',
      );
    }
  }

  Future<ProjectSession> open(String root) async {
    if ((await inspect(root)).kind != DirectoryKind.compatible) {
      throw const StudioException(StudioError.invalidProject, '不能打开此博客目录。');
    }
    return ProjectSession(root: await Directory(root).resolveSymbolicLinks());
  }

  Future<ProjectSession> initialize(String root, {String? templateId}) async {
    await installer.initialize(
      await Directory(root).resolveSymbolicLinks(),
      templateId: templateId,
    );
    return open(root);
  }
}
