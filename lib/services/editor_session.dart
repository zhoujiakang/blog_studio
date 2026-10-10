import 'dart:io';
import 'dart:convert';

import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/storage/recovery_store.dart';
import 'package:blog_studio/services/general_configuration_session.dart';
import 'package:blog_studio/storage/blog_configuration.dart';
import 'package:blog_studio/models/document_editor.dart';
import 'package:blog_studio/services/article_library.dart';
import 'package:blog_studio/services/template_service.dart';
import 'package:blog_studio/services/template_settings_session.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:blog_studio/models/article.dart';
import 'package:blog_studio/models/image.dart';
import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/models/save_state.dart';
import 'package:blog_studio/models/studio_exception.dart';
import 'package:blog_studio/storage/article_repository.dart';
import 'package:blog_studio/storage/template_configuration.dart';
import 'package:blog_studio/models/blog_template.dart';
import 'package:blog_studio/storage/image_importer.dart';
import 'package:blog_studio/services/project_service.dart';
import 'package:blog_studio/storage/trash_repository.dart';
import 'package:blog_studio/storage/taxonomy_preferences.dart';

class EditorSession extends ChangeNotifier {
  EditorSession({required this.editor, ProjectService? projects})
    : projects = projects ?? ProjectService() {
    templates = TemplateService(installer: this.projects.installer);
    editor.addListener(_editorChanged);
    editor.onSave = () => unawaited(flush());
  }
  final DocumentEditor editor;
  final ProjectService projects;
  late final TemplateService templates;
  ProjectSession? project;
  ArticleRepository? repository;
  final settings = TemplateSettingsSession();
  final general = GeneralConfigurationSession();
  BlogConfiguration? get generalConfiguration => general.configuration;
  int get generalGeneration => general.generation;
  bool get generalDirty => general.dirty;
  TemplateConfiguration? get configuration => settings.configuration;
  TaxonomyPreferences? taxonomy;
  final library = ArticleLibrary();
  int get indexRevision => library.revision;
  ArticleIndex get index => library.index;
  set index(ArticleIndex value) => library.index = value;
  ArticleIndex get notes => library.notes;
  set notes(ArticleIndex value) => library.notes = value;
  ArticleSnapshot? article;
  Map<String, dynamic> attributes = {};
  String body = '';
  int revision = 0, savedRevision = 0;
  SaveStatus status = SaveStatus.clean;
  String? error;
  bool busy = false, importing = false, _loading = false;
  Timer? _timer, _externalTimer;
  Future<void> _journal = Future.value();
  bool externalChange = false, _checkingExternal = false;
  List<RecoveryRecord> _recoveries = [];
  bool recovered = false;
  String? recoveryError;
  DateTime? lastSavedAt;
  Future<void> _refreshRecoveries() async {
    try {
      final recovery = RecoveryStore(repository!.store);
      _recoveries = await recovery.list();
      recoveryError = recovery.errors.isEmpty ? null : '部分未保存内容无法读取，本地备份已保留。';
    } catch (e) {
      recoveryError = '无法读取上次未保存的内容，本地备份已保留：$e';
    }
    _notify();
  }

  void _checkpoint() {
    if (article == null || repository == null) return;
    final store = RecoveryStore(repository!.store);
    final record = RecoveryRecord(
      article!,
      body,
      Map.from(attributes),
      DateTime.now(),
    );
    _journal = _journal.then((_) => store.checkpoint(record)).catchError((
      Object e,
    ) {
      recoveryError = '本地备份写入失败，请尽快保存或复制正文。';
      _notify();
    });
  }

  Future<void> checkExternalChanges() async {
    if (_disposed ||
        _checkingExternal ||
        busy ||
        _loading ||
        _saving != null ||
        article == null) {
      return;
    }
    _checkingExternal = true;
    final original = article!;
    final repo = repository!;
    try {
      final file = File(await repo.store.guard.resolve(original.relativePath));
      final changed =
          !await file.exists() ||
          contentHash(await file.readAsBytes()) != original.contentHash;
      if (!_disposed &&
          identical(article, original) &&
          changed &&
          !externalChange) {
        externalChange = true;
        status = SaveStatus.conflict;
        error = '文件已在外部修改或删除。当前内容不会覆盖磁盘版本，可另存副本或重新加载。';
        if (articleDirty) _checkpoint();
        _notify();
      }
    } catch (e) {
      if (!_disposed && identical(article, original)) {
        error = '暂时无法检查磁盘文件：$e';
        _notify();
      }
    } finally {
      _checkingExternal = false;
    }
  }

  Future<void> preservePendingEdits() async {
    if (articleDirty) _checkpoint();
    await _journal;
  }

  Future<bool> _restorePending(RecoveryRecord record) async {
    final file = File(await repository!.store.guard.resolve(record.path));
    final exists = await file.exists();
    final changed =
        !exists ||
        contentHash(await file.readAsBytes()) != record.original.contentHash;
    if (exists && changed) {
      final current = await repository!.read(record.path);
      final sameAttributes =
          current.frontMatter.length == record.attributes.length &&
          record.attributes.entries.every(
            (entry) =>
                jsonEncode(current.frontMatter[entry.key]) ==
                jsonEncode(entry.value),
          );
      if (current.bodySource.trimRight() == record.body.trimRight() &&
          sameAttributes) {
        await RecoveryStore(repository!.store)
            .clear(record.path, record.body, record.attributes);
        _recoveries.removeWhere((item) => item.path == record.path);
        return false;
      }
    }
    await _load(record.original);
    body = record.body;
    attributes = Map.from(record.attributes);
    revision = 1;
    recovered = true;
    await editor.open(
      body,
      images: await ImageImporter(repository!.store).resolveImages(body),
    );
    externalChange = changed;
    status = changed ? SaveStatus.conflict : SaveStatus.dirty;
    if (changed) {
      error = '已恢复上次未保存的内容，但磁盘文件已修改或删除。可另存副本或重新加载，避免覆盖。';
    }
    _notify();
    return true;
  }

  Future<void> _openDocument(String path) async {
    await _refreshRecoveries();
    for (final record in List<RecoveryRecord>.from(_recoveries)) {
      if (record.path == path && await _restorePending(record)) return;
    }
    await _load(await repository!.read(path));
  }

  Future<bool> saveCopy() async {
    if (article == null || busy || importing || editor.composing) return false;
    busy = true;
    _timer?.cancel();
    _notify();
    try {
      await _journal;
      final original = article!;
      final name = attributes['title']?.toString() ?? original.title;
      var copy = original.note
          ? await repository!.createNote()
          : await repository!.create('$name（恢复副本）');
      copy = await repository!.save(copy, body, {
        ...attributes,
        if (!original.note) 'title': '$name（恢复副本）',
      });
      await RecoveryStore(repository!.store)
          .clear(original.relativePath, body, attributes);
      await _load(copy);
      await _refreshRecoveries();
      return true;
    } catch (e) {
      error = '另存失败，当前内容和本地备份已保留：$e';
      _notify();
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool>? _saving;
  bool _disposed = false;
  bool get articleDirty => revision != savedRevision;
  bool get configDirty => settings.dirty;
  bool get dirty => articleDirty || configDirty || generalDirty;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _editorChanged() {
    if (!_loading && article != null && body != editor.markdown) {
      body = editor.markdown;
      _markDirty();
    }
    if (editor.error != null) error = editor.error;
    _notify();
  }

  void _markDirty() {
    revision++;
    _checkpoint();
    if (!externalChange) error = null;
    status = externalChange ? SaveStatus.conflict : SaveStatus.dirty;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 700), () => unawaited(flush()));
    _notify();
  }

  void updateAttributes(Map<String, dynamic> values) {
    if (article == null || busy) return;
    attributes = {...attributes, ...values};
    _markDirty();
  }

  Future<void> refresh() async {
    await library.refresh(repository!);
    _notify();
  }

  Future<bool> flush() {
    _timer?.cancel();
    if (_saving != null) return _saving!;
    return _saving = _saveLoop().whenComplete(() => _saving = null);
  }

  Future<bool> _saveLoop() async {
    await _journal;
    if (externalChange && article != null) return false;
    while (articleDirty && article != null) {
      if (editor.composing) {
        error = '请先完成输入法选字，再保存或切换文章。';
        status = SaveStatus.dirty;
        _notify();
        return false;
      }
      final version = revision;
      final original = article!;
      final capturedBody = body;
      final capturedAttributes = Map<String, dynamic>.from(attributes);
      status = SaveStatus.saving;
      _notify();
      try {
        article = await repository!.save(
          original,
          capturedBody,
          capturedAttributes,
        );
        library.update(article!);
        savedRevision = version;
        lastSavedAt = DateTime.now();
        recovered = false;
        await _journal;
        await RecoveryStore(repository!.store)
            .clear(original.relativePath, capturedBody, capturedAttributes);
        _recoveries.removeWhere(
          (r) => r.path == original.relativePath && !articleDirty,
        );
      } catch (e) {
        error = '$e';
        status = e is StudioException && e.code == StudioError.fileConflict
            ? SaveStatus.conflict
            : SaveStatus.failed;
        _notify();
        return false;
      }
    }
    while (configDirty && configuration != null) {
      status = SaveStatus.saving;
      _notify();
      try {
        await settings.save(repository!.store);
      } catch (e) {
        error = '$e';
        status = e is StudioException && e.code == StudioError.fileConflict
            ? SaveStatus.conflict
            : SaveStatus.failed;
        _notify();
        return false;
      }
    }
    while (generalDirty && generalConfiguration != null) {
      status = SaveStatus.saving;
      _notify();
      try {
        await general.save(repository!.store);
      } catch (e) {
        error = '$e';
        status = e is StudioException && e.code == StudioError.fileConflict
            ? SaveStatus.conflict
            : SaveStatus.failed;
        _notify();
        return false;
      }
    }
    status = SaveStatus.clean;
    error = null;
    _notify();
    return true;
  }

  Future<bool> _operation(Future<void> Function() action) async {
    if (busy || importing) return false;
    busy = true;
    _notify();
    try {
      if (!await flush()) return false;
      await action();
      return true;
    } catch (e) {
      error = '$e';
      _notify();
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> openProject(
    String root, {
    bool initialize = false,
    String? templateId,
  }) => _operation(() async {
    final service = projects;
    final next = initialize
        ? await service.initialize(root, templateId: templateId)
        : await service.open(root);
    final nextRepository = ArticleRepository(next.root);
    final nextIndex = await nextRepository.scan();
    final nextNotes = await nextRepository.scan(notes: true);
    final nextTaxonomy = TaxonomyPreferences(nextRepository.store);
    await nextTaxonomy.load();
    final nextConfiguration = await TemplateConfiguration.load(
      nextRepository.store,
    );
    final nextGeneral = await BlogConfiguration.load(nextRepository.store);
    article = null;
    settings.load(nextConfiguration);
    general.load(nextGeneral);
    project = next;
    repository = nextRepository;
    taxonomy = nextTaxonomy;
    library.load(nextIndex, nextNotes);
    attributes = {};
    body = '';
    revision = savedRevision = 0;
    externalChange = false;
    _externalTimer?.cancel();
    _externalTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(checkExternalChanges()),
    );
    await _refreshRecoveries();
    for (final record in List<RecoveryRecord>.from(_recoveries)) {
      if (await _restorePending(record)) break;
    }
  });
  Future<void> _load(ArticleSnapshot next) async {
    final images = await ImageImporter(repository!.store)
        .resolveImages(next.bodySource);
    _loading = true;
    try {
      article = next;
      library.update(next);
      body = next.bodySource;
      attributes = Map.from(next.frontMatter);
      revision = savedRevision = 0;
      status = SaveStatus.clean;
      recovered = false;
      lastSavedAt = null;
      externalChange = false;
      error = null;
      await editor.open(body, images: images);
    } finally {
      _loading = false;
    }
    _notify();
  }

  Future<bool> openArticle(String path) =>
      _operation(() => _openDocument(path));
  Future<bool> openAbout() => _operation(() async {
    await repository!.openAbout();
    await _openDocument('resource/about.md');
  });

  void updateGeneralConfiguration(String key, String value) {
    if (generalConfiguration == null || busy) return;
    general.change(key, value);
    error = null;
    status = SaveStatus.dirty;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 700), () => unawaited(flush()));
    _notify();
  }

  Future<void> reloadGeneralConfiguration() async {
    if (busy || importing) return;
    _timer?.cancel();
    if (_saving != null) await _saving;
    try {
      general.load(await BlogConfiguration.load(repository!.store));

      status = SaveStatus.clean;
      error = null;
    } catch (e) {
      error = '$e';
    }
    _notify();
  }

  void updateConfiguration(String key, String value) {
    if (configuration == null || busy) return;
    try {
      settings.change(key, value);
      error = null;
      status = SaveStatus.dirty;
      _timer?.cancel();
      _timer = Timer(
        const Duration(milliseconds: 700),
        () => unawaited(flush()),
      );
    } catch (e) {
      error = '$e';
    }
    _notify();
  }

  void resetConfiguration() {
    if (busy || configuration == null) return;
    settings.reset();
    status = SaveStatus.dirty;
    error = null;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 700), () => unawaited(flush()));
    _notify();
  }

  Future<void> reloadConfiguration() async {
    if (busy || importing) return;
    _timer?.cancel();
    if (_saving != null) await _saving;
    try {
      settings.load(await TemplateConfiguration.load(repository!.store));
      status = SaveStatus.clean;
      error = null;
    } catch (e) {
      error = '$e';
    }
    _notify();
  }

  Future<void> setGeneralAvatar(ImageInput input) async {
    if (busy || importing || generalConfiguration == null) return;
    importing = true;
    _notify();
    try {
      final image = await ImageImporter(repository!.store).import(input);
      updateGeneralConfiguration('avatar', image.markdownUrl);
    } catch (e) {
      error = '$e';
    } finally {
      importing = false;
      _notify();
    }
  }

  Future<void> setConfigurationImage(String key, ImageInput input) async {
    if (busy || importing) return;
    importing = true;
    _notify();
    try {
      final image = await ImageImporter(repository!.store).import(input);
      updateConfiguration(key, image.markdownUrl);
    } catch (e) {
      error = '$e';
    } finally {
      importing = false;
      _notify();
    }
  }

  Future<List<BlogTemplate>> availableStyles() =>
      templates.available(repository!.store);
  Future<bool> switchStyle(String id) => _operation(() async {
    settings.load(await templates.activate(project!, repository!.store, id));
    general.load(await BlogConfiguration.load(repository!.store));
    article = null;
    await refresh();
  });

  Future<bool> createArticle(String title) => _operation(() async {
    await _load(await repository!.create(title));
  });
  Future<bool> createNote() => _operation(() async {
    await _load(await repository!.createNote());
  });

  Future<void> insertNote(String path) async {
    if (article == null || !article!.post || busy || importing) return;
    if (editor.composing) {
      error = '请先完成输入法选字，再引用小记。';
      _notify();
      return;
    }
    importing = true;
    error = null;
    _notify();
    final currentSession = editor.documentId;
    try {
      final note = await repository!.read(path);
      if (!note.note) throw StateError('只能引用小记。');
      final images = await ImageImporter(repository!.store)
          .resolveImages(note.bodySource);
      if (currentSession != editor.documentId) {
        throw StateError('文章已切换，请重新引用。');
      }
      await editor.insertMarkdown(note.bodySource, images: images);
    } catch (e) {
      error = '$e';
    } finally {
      importing = false;
      _notify();
    }
  }

  Future<bool> closeArticle() {
    // Changing a library filter needs no disk operation or busy-state transition.
    if (article == null && !dirty) return Future.value(!busy && !importing);
    return _operation(() async {
      article = null;
      _notify();
    });
  }

  Future<bool> changeDraft(bool draft, {String? path}) => _operation(() async {
    final target = path == null ? article! : await repository!.read(path);
    final next = await repository!.setDraft(target, draft);
    library.update(next, previousPath: target.relativePath);
    if (article?.relativePath == target.relativePath) await _load(next);
  });
  Future<bool> deleteArticle({String? path}) => _operation(() async {
    final target = path == null ? article! : await repository!.read(path);
    await TrashRepository(repository!.store).remove(target);
    if (article?.relativePath == target.relativePath) article = null;
    library.remove(target.relativePath);
  });
  Future<bool> restore(String id) => _operation(() async {
    final trash = TrashRepository(repository!.store);
    final entry = (await trash.list()).firstWhere((e) => e.id == id);
    await trash.restore(entry);
    library.update(await repository!.read(entry.originalPath));
  });
  Future<void> reload() async {
    if (busy || importing || article == null) return;
    _timer?.cancel();
    if (_saving != null) await _saving;
    await _journal;
    await _load(await repository!.read(article!.relativePath));
    await _refreshRecoveries();
  }

  Future<void> insertImage(ImageInput input) async {
    if (article == null || busy || importing) return;
    importing = true;
    error = null;
    _notify();
    final session = editor.documentId;
    try {
      await editor.bookmarkImageSelection();
      final image = await ImageImporter(repository!.store).import(input);
      if (session != editor.documentId) throw StateError('文章已切换，请重新插图。');
      await editor.insertImage(image, input.bytes);
    } catch (e) {
      error = '$e';
    } finally {
      importing = false;
      _notify();
    }
  }

  Future<void> setCover(ImageInput input) async {
    if (article == null || busy || importing) return;
    importing = true;
    error = null;
    _notify();
    final original = article!.relativePath;
    try {
      final image = await ImageImporter(repository!.store).import(input);
      if (article?.relativePath != original) throw StateError('文章已切换，请重新选择封面。');
      updateAttributes({'cover': image.markdownUrl});
    } catch (e) {
      error = '$e';
    } finally {
      importing = false;
      _notify();
    }
  }

  Future<void> toggleTaxonomyPin(String key, String value) async {
    if (!await _operation(() => taxonomy!.toggle(key, value))) {
      throw StateError(error ?? '操作正在进行，请稍后再试。');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _externalTimer?.cancel();
    editor.removeListener(_editorChanged);
    editor.dispose();
    super.dispose();
  }
}
