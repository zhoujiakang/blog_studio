import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/app/app_dependencies.dart';
import 'package:blog_studio/controllers/studio_controller.dart';
import 'package:blog_studio/services/editor_session.dart';
import 'package:blog_studio/services/project_service.dart';
import 'package:blog_studio/services/template_installer.dart';
import 'package:blog_studio/storage/last_project_store.dart';

import 'studio_controller_test.dart'
    show TestEditor, TestPreview, TestPrompts, TestFiles;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'app-local history persists serial writes and tolerates damaged records',
    () async {
      final root = await Directory.systemTemp.createTemp('last-project-state-');
      final file = File('${root.path}/app/session.json');
      final history = LastProjectStore(file);
      try {
        expect(await history.read(), isNull);
        await Future.wait([
          history.remember('/first'),
          history.remember('/second'),
        ]);
        expect(await LastProjectStore(file).read(), '/second');
        await file.writeAsString('{broken');
        expect(await history.read(), isNull);
        await history.remember(null);
        expect(await history.read(), isNull);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  for (final valid in [true, false]) {
    test('startup restores only a valid existing blog: $valid', () async {
      final root = await Directory.systemTemp.createTemp('last-project-blog-');
      final blog = await Directory('${root.path}/blog').create();
      final canonical = await blog.resolveSymbolicLinks();
      final history = LastProjectStore(File('${root.path}/app/session.json'));
      final service = ProjectService(
        installer: TemplateInstaller(
          readAsset: (name) => File(name).readAsBytes(),
        ),
      );
      final session = EditorSession(editor: TestEditor(), projects: service);
      final preview = TestPreview();
      final controller = StudioController(
        session: session,
        preview: preview,
        prompts: TestPrompts(),
        dependencies: AppDependencies.macos,
        lastProject: history,
      );
      try {
        if (valid) await service.initialize(blog.path, templateId: 'butterfly');
        await history.remember(blog.path);
        expect(controller.creationBlocked, true);
        await controller.restoreLastProject();
        expect(controller.restoringProject, false);
        expect(controller.creationBlocked, false);
        expect(session.project?.root, valid ? canonical : null);
        expect(await history.read(), valid ? blog.path : null);
        expect(preview.url, isNull);
        if (!valid) expect(await blog.list().toList(), isEmpty);
      } finally {
        controller.dispose();
        session.dispose();
        preview.dispose();
        await root.delete(recursive: true);
      }
    });
  }

  test('successful selection is remembered; cancelled and failed selections keep it', () async {
    final root = await Directory.systemTemp.createTemp(
      'last-project-selection-',
    );
    final blog = await Directory('${root.path}/blog').create();
    final canonical = await blog.resolveSymbolicLinks();
    final history = LastProjectStore(File('${root.path}/app/session.json'));
    final service = ProjectService(
      installer: TemplateInstaller(
        readAsset: (name) => File(name).readAsBytes(),
      ),
    );
    final session = EditorSession(editor: TestEditor(), projects: service);
    final preview = TestPreview();
    final files = TestFiles()..root = blog.path;
    final base = AppDependencies.macos;
    final dependencies = AppDependencies(
      files: files,
      clipboard: base.clipboard,
      window: base.window,
      browser: base.browser,
      runtime: base.runtime,
      processes: base.processes,
      createEditorHost: base.createEditorHost,
    );
    final controller = StudioController(
      session: session,
      preview: preview,
      prompts: TestPrompts(),
      dependencies: dependencies,
      lastProject: history,
    );
    try {
      await service.initialize(blog.path, templateId: 'butterfly');
      await controller.restoreLastProject();
      await controller.pickProject();
      expect(await history.read(), canonical);
      files.root = null;
      await controller.pickProject();
      expect(await history.read(), canonical);
      files.root = '${root.path}/missing';
      await controller.pickProject();
      expect(await history.read(), canonical);
      expect(session.project!.root, canonical);
    } finally {
      controller.dispose();
      session.dispose();
      preview.dispose();
      await root.delete(recursive: true);
    }
  });
}
