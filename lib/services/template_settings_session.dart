import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/storage/template_configuration.dart';

/// Independent configuration revisions. Workspace flush coordinates this with document saves.
class TemplateSettingsSession {
  TemplateConfiguration? configuration;
  int revision = 0, savedRevision = 0;
  bool get dirty => revision != savedRevision;
  void load(TemplateConfiguration next) {
    configuration = next;
    revision = savedRevision = 0;
  }

  void change(String key, String value) {
    configuration = configuration!.change(key, value);
    revision++;
  }

  void reset() {
    configuration = configuration!.defaults();
    revision++;
  }

  Future<void> save(FileStore store) async {
    final capturedRevision = revision;
    final captured = configuration!;
    final saved = await captured.save(store);
    // Retain newer in-memory values while advancing the disk hash of the saved revision.
    configuration = TemplateConfiguration(
      saved.path,
      configuration!.document,
      saved.hash,
    );
    savedRevision = capturedRevision;
  }
}
