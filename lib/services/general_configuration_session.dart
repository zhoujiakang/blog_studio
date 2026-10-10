import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/storage/blog_configuration.dart';

/// Owns common settings; the workspace coordinates saves with other documents.
class GeneralConfigurationSession {
  BlogConfiguration? configuration;
  int revision = 0, savedRevision = 0, generation = 0;
  bool get dirty => revision != savedRevision;

  void load(BlogConfiguration next) {
    configuration = next;
    revision = savedRevision = 0;
    generation++;
  }

  void change(String key, String value) {
    configuration = configuration!.change(key, value);
    revision++;
  }

  Future<void> save(FileStore store) async {
    final captured = configuration!;
    final capturedRevision = revision;
    final saved = await captured.save(store);
    configuration = BlogConfiguration(configuration!.document, saved.hash);
    savedRevision = capturedRevision;
  }
}
