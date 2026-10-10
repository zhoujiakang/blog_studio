import 'dart:io';

import 'package:blog_studio/storage/resource_layout.dart';

import 'dart:convert';

import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/services/blog_layout_service.dart';
import 'package:blog_studio/models/blog_template.dart';
import 'package:blog_studio/services/template_installer.dart';
import 'package:blog_studio/storage/template_configuration.dart';

class TemplateService {
  TemplateService({TemplateInstaller? installer})
    : installer = installer ?? TemplateInstaller();
  final TemplateInstaller installer;
  Future<List<BlogTemplate>> available(FileStore store) async {
    final result = <String, BlogTemplate>{};
    final dir = Directory(
      await store.guard.resolve(
        ResourceLayout(store.guard.root).templateDirectory,
      ),
    );
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final id = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (!BlogLayoutService.validId(id)) continue;
      try {
        final doc = jsonDecode(
          utf8.decode(
            await store.read(
              '${ResourceLayout(store.guard.root).templateDirectory}/$id/template.json',
            ),
          ),
        ) as Map;
        TemplateConfiguration.validate(Map<String, dynamic>.from(doc));
        if (doc['id'] == id) {
          result[id] = BlogTemplate(id: id, name: doc['name'], files: []);
        }
      } catch (_) {
        /* Invalid local styles never become selectable. */
      }
    }
    try {
      for (final template in await installer.listTemplates()) {
        result.putIfAbsent(template.id, () => template);
      }
    } catch (_) {
      // Installed themes remain selectable when GitHub is unavailable.
      if (result.isEmpty) rethrow;
    }
    return result.values.toList();
  }

  Future<TemplateConfiguration> activate(
    ProjectSession project,
    FileStore store,
    String id,
  ) async {
    final dir = Directory(
      await store.guard.resolve(
        '${ResourceLayout(store.guard.root).templateDirectory}/$id',
      ),
    );
    if (!await dir.exists()) {
      await installer.installStyle(project.root, id);
    }
    // Validate the configuration before the activation marker can change.
    final doc = jsonDecode(
      utf8.decode(
        await store.read(
          '${ResourceLayout(store.guard.root).templateDirectory}/$id/template.json',
        ),
      ),
    ) as Map;
    TemplateConfiguration.validate(Map<String, dynamic>.from(doc));
    await BlogLayoutService(project.root).activate(id);
    return TemplateConfiguration.load(store);
  }
}
