import 'package:blog_studio/controllers/publish_controller.dart';
import 'package:blog_studio/platform/contracts/desktop_platform.dart';
import 'package:blog_studio/storage/image_importer.dart';
import 'package:blog_studio/models/studio_exception.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:blog_studio/app/app_dependencies.dart';
import 'package:blog_studio/controllers/interaction_prompts.dart';
import 'package:blog_studio/services/editor_session.dart';
import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/services/preview_manager.dart';
import 'package:blog_studio/models/runtime_environment.dart';
import 'package:blog_studio/models/dependency_report.dart';
import 'package:blog_studio/services/managed_runtime.dart';

class StudioController extends ChangeNotifier {
  StudioController({
    required this.session,
    required this.preview,
    required this.prompts,
    required this.dependencies,
    this.publisher,
  }) {
    session.addListener(_changed);
    preview.addListener(_changed);
    publisher?.addListener(_changed);
    session.editor.onPasteImage = () => unawaited(pasteImage());
  }
  final PublishController? publisher;
  final EditorSession session;
  final PreviewManager preview;
  final InteractionPrompts prompts;
  final AppDependencies dependencies;
  bool preparingPreview = false, properties = false, noteReference = false;
  bool closing = false, dragging = false, categoryBrowser = false;
  bool _switchingSection = false;
  bool choosingProject = false;

  /// Navigation must not animate creation controls into a disabled state.
  bool get creationBlocked =>
      (session.busy && !_switchingSection) ||
      session.importing ||
      preparingPreview ||
      choosingProject ||
      ((publisher?.busy ?? false) && !_switchingSection);
  bool get _operationBlocked =>
      _switchingSection ||
      session.busy ||
      session.importing ||
      preparingPreview ||
      choosingProject ||
      (publisher?.busy ?? false);
  String filter = 'all';
  String? selectedTag, selectedCategory;
  String query = '';
  int _previewRevision = -1;
  bool _disposed = false;
  bool get mounted => !_disposed;
  void update(VoidCallback action) {
    action();
    if (mounted) notifyListeners();
  }

  void _changed() {
    if (preview.url != null &&
        session.indexRevision != _previewRevision &&
        !session.dirty) {
      _previewRevision = session.indexRevision;
      unawaited(
        preview.refresh().catchError((Object e) => _message('预览更新失败：$e')),
      );
    }
    if (mounted) notifyListeners();
  }

  void _message(String text) {
    if (mounted) prompts.message(text);
  }

  Future<bool> _confirm(String title, String message, String action) =>
      prompts.confirm(title, message, action);
  Future<void> run(Future<bool> action) async {
    if (!await action && session.error != null) _message(session.error!);
  }

  Future<void> selectSection(String value) async {
    if (_operationBlocked) return;
    if (filter == value &&
        (value == 'about'
            ? session.article?.about == true
            : session.article == null)) {
      return;
    }
    _switchingSection = true;
    try {
      if (!await session.closeArticle()) {
        if (session.error != null) _message(session.error!);
        return;
      }
      if (!mounted) return;
      if (value == 'about' && !await session.openAbout()) {
        if (session.error != null) _message(session.error!);
        return;
      }
      if (!mounted) return;
      update(() {
        filter = value;
        properties = noteReference = false;
      });
      if (value == 'publish' && publisher != null && session.project != null) {
        await publisher!.open(session.project!, session.repository!.store);
      }
    } finally {
      _switchingSection = false;
      if (mounted) notifyListeners();
    }
  }

  Future<void> openArticle(String path) async {
    if (_operationBlocked) return;
    _switchingSection = true;
    try {
      await run(session.openArticle(path));
    } finally {
      _switchingSection = false;
      if (mounted) notifyListeners();
    }
  }

  Future<void> returnToLibrary() async {
    if (_operationBlocked || session.article == null) return;
    final about = session.article!.about;
    _switchingSection = true;
    try {
      await run(session.closeArticle());
      if (about && session.article == null && mounted) {
        update(() => filter = 'all');
      }
    } finally {
      _switchingSection = false;
      if (mounted) notifyListeners();
    }
  }

  Future<void> manageArticle(String action, String path, bool draft) async {
    if (action == 'state') {
      await run(session.changeDraft(!draft, path: path));
    } else if (action == 'delete' &&
        await _confirm('移入回收区', '文章可在回收区恢复，图片会保留。', '移入回收区')) {
      await run(session.deleteArticle(path: path));
    }
  }

  Future<void> reloadDocument() async {
    if (await _confirm('重新加载', '将丢弃当前未保存的修改，读取磁盘版本。', '重新加载')) {
      try {
        await session.reload();
      } catch (e) {
        _message('$e');
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_changed);
    preview.removeListener(_changed);
    publisher?.removeListener(_changed);
    session.editor.onPasteImage = null;
    super.dispose();
  }

  Future<void> pickProject() async {
    if (_operationBlocked) return;
    final root = await dependencies.files.chooseBlogDirectory();
    if (root == null || !mounted) return;
    update(() => choosingProject = true);
    try {
      final inspection = await session.projects.inspect(root);
      if (!mounted) return;
      if (inspection.kind == DirectoryKind.incompatible) {
        _message(inspection.reason!);
        return;
      }
      final initialize = inspection.kind == DirectoryKind.empty;
      String? templateId;
      if (initialize) {
        final templates = await session.projects.installer.listTemplates();
        if (!mounted) return;
        templateId = await prompts.chooseInitialTemplate(root, templates);
        if (templateId == null || !mounted) return;
      }
      if (!await session.flush()) {
        _message(session.error ?? "保存失败");
        return;
      }
      await preview.stop();
      await run(
        session.openProject(
          root,
          initialize: initialize,
          templateId: templateId,
        ),
      );
      if (mounted) {
        update(_resetLibraryView);
      }
    } catch (e) {
      _message('$e');
    } finally {
      update(() => choosingProject = false);
    }
  }

  void _resetLibraryView({String section = 'all'}) {
    filter = section;
    properties = noteReference = categoryBrowser = dragging = false;
    query = '';
    selectedTag = selectedCategory = null;
  }

  Future<void> newArticle() async {
    if (_operationBlocked) return;
    final value = await prompts.newArticleTitle();
    if (value != null) {
      final success = await session.createArticle(value);
      if (!success && session.error != null) _message(session.error!);
      if (success && mounted) {
        update(_resetLibraryView);
      }
    }
  }

  Future<void> newNote() async {
    if (_operationBlocked) return;
    final success = await session.createNote();
    if (!success && session.error != null) _message(session.error!);
    if (success && mounted) {
      update(() => _resetLibraryView(section: 'notes'));
    }
  }

  bool _checkImageTarget(String document, Object? repository) {
    if (!mounted) return false;
    if (document == session.editor.documentId &&
        identical(repository, session.repository)) {
      return true;
    }
    _message('文章已切换，请在当前文章重新插图。');
    return false;
  }

  Future<void> pickImage() async {
    final document = session.editor.documentId;
    final repository = session.repository;
    try {
      final image = await dependencies.files.chooseImage(label: '图片');
      if (image != null && _checkImageTarget(document, repository)) {
        await session.insertImage(image);
        if (session.error != null) _message(session.error!);
      }
    } catch (e) {
      _message('$e');
    }
  }

  Future<void> pickCover() async {
    final document = session.editor.documentId;
    final repository = session.repository;
    try {
      final image = await dependencies.files.chooseImage(label: '封面图片');
      if (image != null && _checkImageTarget(document, repository)) {
        await session.setCover(image);
        if (session.error != null) _message(session.error!);
      }
    } catch (e) {
      _message('$e');
    }
  }

  Future<void> pickAvatar() async {
    if (_operationBlocked) return;
    final repository = session.repository;
    try {
      final image = await dependencies.files.chooseImage(label: '头像图片');
      if (image == null ||
          !mounted ||
          !identical(repository, session.repository)) {
        return;
      }
      await session.setGeneralAvatar(image);
      if (session.error != null) _message(session.error!);
    } catch (e) {
      _message('$e');
    }
  }

  Future<void> pickConfigurationImage(String key) async {
    final path = session.configuration?.path;
    try {
      final image = await dependencies.files.chooseImage();
      if (image == null || !mounted || path != session.configuration?.path) {
        return;
      }
      await session.setConfigurationImage(key, image);
      if (session.error != null) _message(session.error!);
    } catch (e) {
      _message('$e');
    }
  }

  Future<void> pasteImage() async {
    final document = session.editor.documentId;
    final repository = session.repository;
    try {
      final image = await dependencies.clipboard.readImage();
      if (image == null) {
        _message('剪贴板中没有可用的图片。');
        return;
      }
      if (!_checkImageTarget(document, repository)) return;
      await session.insertImage(image);
    } catch (e) {
      _message('读取剪贴板失败：$e');
    }
  }

  Future<void> openPreview() async {
    if ((publisher?.busy ?? false) ||
        preparingPreview ||
        session.project == null ||
        session.busy ||
        session.importing) {
      return;
    }
    if (!await session.flush()) {
      _message(session.error ?? '保存失败');
      return;
    }
    update(() => preparingPreview = true);
    try {
      final project = session.project!;
      final runtime = await preview.detectRuntime(project);
      final report = runtime.status == RuntimeStatus.ready
          ? await preview.inspect(project, runtime)
          : null;
      final needsPreparation =
          runtime.status != RuntimeStatus.ready ||
          report?.status != DependencyStatus.ready;
      if (needsPreparation) {
        if (!mounted ||
            !await _confirm(
              '首次预览需要准备一下',
              '应用会自动下载并准备预览所需组件，完成后打开博客。通常只需准备一次，文章和图片会保留。',
              '一键准备并预览',
            )) {
          return;
        }
      }
      if (!mounted) return;
      final url = await prompts.preparePreview(project, runtime, report);
      if (url == null) return;
      await dependencies.browser.open(url);
    } on PreviewPreparationCancelled {
      // Cancellation is a normal result, not an error for the user.
    } catch (_) {
      _message('暂时无法打开预览，请检查网络后重试。');
    } finally {
      if (mounted) update(() => preparingPreview = false);
    }
  }

  void handleFileDrop(FileDropEvent event) {
    update(() => dragging = event.hovering);
    if (event.paths.isNotEmpty) unawaited(insertDroppedImages(event.paths));
  }

  Future<void> insertDroppedImages(List<String> paths) async {
    final document = session.editor.documentId;
    final repository = session.repository;
    try {
      for (final path in paths) {
        final image = await ImageImporter.readFile(path);
        if (!_checkImageTarget(document, repository)) return;
        await session.insertImage(image);
        if (session.error != null) {
          _message(session.error!);
          return;
        }
      }
    } catch (e) {
      _message(e is StudioException ? e.toString() : '无法读取拖入的图片，请重新选择。');
    }
  }

  Future<void> copy() async {
    await dependencies.clipboard.writeText(
      session.article == null ? '' : await session.editor.serialize(),
    );
    _message('正文 Markdown 已复制');
  }

  Future<void> close() async {
    if (closing ||
        session.importing ||
        session.busy ||
        preparingPreview ||
        (publisher?.busy ?? false)) {
      return;
    }
    closing = true;
    try {
      if (!await session.flush()) {
        if (!mounted ||
            !await _confirm(
              '尚未保存',
              '${session.error}\n\n关闭将丢弃当前未保存的修改。',
              '丢弃并关闭',
            )) {
          return;
        }
      }
      await preview.shutdown();
      await dependencies.window.quit();
    } finally {
      closing = false;
    }
  }

  Future<void> switchStyle() async {
    if (!await session.flush() || !mounted) return;
    try {
      final styles = await session.availableStyles();
      if (!mounted) return;
      final selected = await prompts.chooseStyle(styles);
      if (selected == null ||
          !mounted ||
          selected == session.configuration!.document['id']) {
        return;
      }
      await preview.stop();
      await run(session.switchStyle(selected));
    } catch (e) {
      _message('$e');
    }
  }
}
