import 'dart:async';
import 'dart:io';

import 'package:blog_studio/services/template_installer.dart';
import 'package:blog_studio/services/project_service.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/app/app_dependencies.dart';
import 'package:blog_studio/controllers/interaction_prompts.dart';
import 'package:blog_studio/controllers/studio_controller.dart';
import 'package:blog_studio/platform/contracts/desktop_platform.dart';
import 'package:blog_studio/models/image.dart';
import 'package:blog_studio/services/editor_session.dart';
import 'package:blog_studio/controllers/web_markdown_controller.dart';
import 'package:blog_studio/models/blog_template.dart';
import 'package:blog_studio/services/preview_manager.dart';
import 'package:blog_studio/models/runtime_environment.dart';
import 'package:blog_studio/models/dependency_report.dart';
import 'package:blog_studio/models/project.dart';

class TestFiles implements FileDialogs {
  String? root;
  @override
  Future<String?> chooseBlogDirectory() async => root;
  @override
  Future<ImageInput?> chooseImage({String label = '图片'}) async => null;
}

class TestPrompts implements InteractionPrompts {
  bool discard = false;
  String? template;
  final messages = <String>[];
  int newArticleRequests = 0;
  @override
  void message(String text) => messages.add(text);
  @override
  Future<bool> confirm(String title, String message, String action) async =>
      discard;
  @override
  Future<String?> chooseInitialTemplate(
    String root,
    List<BlogTemplate> templates,
  ) async => template;
  @override
  Future<String?> newArticleTitle() async {
    newArticleRequests++;
    return null;
  }

  @override
  Future<String?> chooseStyle(List<BlogTemplate> styles) async => null;
  @override
  Future<Uri?> preparePreview(
    ProjectSession project,
    RuntimeEnvironment runtime,
    DependencyReport? report,
  ) async => null;
}

class TestWindow implements DesktopWindow {
  int quits = 0;
  @override
  Future<void> initialize() async {}
  @override
  void watchClose(void Function() callback) {}
  @override
  void unwatchClose(void Function() callback) {}
  @override
  Future<void> quit() async {
    quits++;
  }
}

class TestPreview extends PreviewManager {
  int stops = 0;
  @override
  Future<void> stop() async {
    stops++;
  }
}

class TestEditor extends WebMarkdownController {
  void type(String text) {
    protocol.markdown = text;
    notifyListeners();
  }
}

class DropRecordingSession extends EditorSession {
  DropRecordingSession() : super(editor: WebMarkdownController());
  final received = Completer<ImageInput>();
  @override
  Future<void> insertImage(ImageInput input) async {
    received.complete(input);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a generic drop event routes file bytes through the shared image flow',
    () async {
      final directory = await Directory.systemTemp.createTemp('inkjian-drop-');
      final image = File('${directory.path}/日常.png');
      await image.writeAsBytes([1, 2, 3, 4]);
      final session = DropRecordingSession();
      final preview = TestPreview();
      final prompts = TestPrompts();
      final controller = StudioController(
        session: session,
        preview: preview,
        prompts: prompts,
        dependencies: AppDependencies.macos,
      );
      try {
        controller.handleFileDrop(const FileDropEvent(hovering: true));
        expect(controller.dragging, true);
        controller.handleFileDrop(FileDropEvent(paths: [image.path]));
        final input = await session.received.future.timeout(
          const Duration(seconds: 2),
        );
        expect(controller.dragging, false);
        expect(input.name, '日常.png');
        expect(input.bytes, [1, 2, 3, 4]);
        await controller.insertDroppedImages(['${directory.path}/missing.png']);
        expect(prompts.messages.single, '无法读取拖入的图片，请重新选择。');
      } finally {
        controller.dispose();
        preview.dispose();
        session.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
  test('About and configuration navigation keep creation controls stable and reject concurrent creation', () async {
    final root = await Directory.systemTemp.createTemp('studio-navigation-');
    final session = EditorSession(
      editor: TestEditor(),
      projects: ProjectService(
        installer: TemplateInstaller(
          readAsset: (path) => File(path).readAsBytes(),
        ),
      ),
    );
    final preview = TestPreview();
    final prompts = TestPrompts();
    final controller = StudioController(
      session: session,
      preview: preview,
      prompts: prompts,
      dependencies: AppDependencies.macos,
    );
    try {
      expect(await session.openProject(root.path, initialize: true), true);
      final disabledDuringNavigation = <bool>[];
      var sawBusy = false;
      void observe() {
        disabledDuringNavigation.add(controller.creationBlocked);
        if (session.busy) {
          sawBusy = true;
          controller.newArticle();
          controller.newNote();
        }
      }

      controller.addListener(observe);
      await controller.selectSection('about');
      expect(session.article?.about, true);
      await controller.selectSection('configuration');
      expect(session.article, isNull);
      expect(controller.filter, 'configuration');
      expect(sawBusy, true);
      expect(disabledDuringNavigation, everyElement(false));
      expect(prompts.newArticleRequests, 0);
      expect(session.notes.articles, isEmpty);
      controller.removeListener(observe);
      session.busy = true;
      expect(controller.creationBlocked, true);
      session.busy = false;
    } finally {
      controller.dispose();
      preview.dispose();
      session.dispose();
      await root.delete(recursive: true);
    }
  });
  test('cancel initialization and refuse conflicted switch without losing current document', () async {
    final root = await Directory.systemTemp.createTemp('studio-controller-');
    final empty = await Directory.systemTemp.createTemp(
      'studio-controller-empty-',
    );
    final editor = TestEditor();
    final session = EditorSession(
      editor: editor,
      projects: ProjectService(
        installer: TemplateInstaller(
          readAsset: (path) => File(path).readAsBytes(),
        ),
      ),
    );
    final preview = TestPreview();
    final prompts = TestPrompts();
    final files = TestFiles()..root = empty.path;
    final window = TestWindow();
    final defaults = AppDependencies.macos;
    final dependencies = AppDependencies(
      files: files,
      clipboard: defaults.clipboard,
      window: window,
      browser: defaults.browser,
      runtime: defaults.runtime,
      processes: defaults.processes,
      createEditorHost: defaults.createEditorHost,
    );
    final controller = StudioController(
      session: session,
      preview: preview,
      prompts: prompts,
      dependencies: dependencies,
    );
    try {
      expect(await session.openProject(root.path, initialize: true), true);
      expect(await session.createArticle('保留当前文章'), true);
      final article = session.article!;
      await controller
          .pickProject(); // Empty directory, user cancels template selection.
      expect(session.project!.root, await root.resolveSymbolicLinks());
      expect(session.article!.relativePath, article.relativePath);
      expect(await empty.list().toList(), isEmpty);
      expect(preview.stops, 0);
      await File('${root.path}/${article.relativePath}')
          .writeAsString('外部修改\n');
      editor.type('尚未保存的输入\n');
      prompts.template = 'butterfly';
      await controller.pickProject();
      expect(session.project!.root, await root.resolveSymbolicLinks());
      expect(session.body, '尚未保存的输入\n');
      expect(preview.stops, 0);
      expect(await empty.list().toList(), isEmpty);
      await controller.close();
      expect(window.quits, 0);
      prompts.discard = true;
      await controller.close();
      expect(window.quits, 1);
      expect(
        await File('${root.path}/${article.relativePath}').readAsString(),
        '外部修改\n',
      );
    } finally {
      controller.dispose();
      preview.dispose();
      session.dispose();
      await root.delete(recursive: true);
      await empty.delete(recursive: true);
    }
  });
}
