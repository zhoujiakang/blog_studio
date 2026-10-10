import 'package:blog_studio/models/article.dart';
import 'package:blog_studio/storage/article_repository.dart';

/// In-memory indexes: disk scans are explicit; successful local writes update
/// only their own entry. External edits are picked up by refresh or reopening.
class ArticleLibrary {
  ArticleIndex index = const ArticleIndex([]);
  ArticleIndex notes = const ArticleIndex([]);
  int revision = 0;

  void load(ArticleIndex articles, ArticleIndex noteEntries) {
    index = articles;
    notes = noteEntries;
    revision++;
  }

  Future<void> refresh(ArticleRepository repository) async {
    final nextIndex = await repository.scan();
    final nextNotes = await repository.scan(notes: true);
    load(nextIndex, nextNotes);
  }

  void update(ArticleSnapshot snapshot, {String? previousPath}) {
    if (snapshot.about) return;
    if (previousPath != null && previousPath != snapshot.relativePath) {
      remove(previousPath);
    }
    final current = snapshot.note ? notes : index;
    final entries =
        current.articles
            .where((entry) => entry.relativePath != snapshot.relativePath)
            .toList()
          ..add(ArticleSummary.fromSnapshot(snapshot))
          ..sort((a, b) => b.date.compareTo(a.date));
    final errors = Map<String, String>.from(current.errors)
      ..remove(snapshot.relativePath);
    final next = ArticleIndex(entries, errors: errors);
    if (snapshot.note) {
      notes = next;
    } else {
      index = next;
    }
    revision++;
  }

  void remove(String path) {
    final current = path.startsWith('resource/notes/') ? notes : index;
    final next = ArticleIndex(
      current.articles.where((entry) => entry.relativePath != path).toList(),
      errors: Map<String, String>.from(current.errors)..remove(path),
    );
    if (path.startsWith('resource/notes/')) {
      notes = next;
    } else {
      index = next;
    }
    revision++;
  }
}
