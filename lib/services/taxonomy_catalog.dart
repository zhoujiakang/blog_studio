import 'package:blog_studio/models/article.dart';

class TaxonomyCatalog {
  TaxonomyCatalog(List<ArticleSummary> articles, String key) {
    List<String> values(ArticleSummary article) =>
        key == 'tags' ? article.tags : article.categories;
    for (final article in articles) {
      for (final value in values(article).toSet()) {
        counts[value] = (counts[value] ?? 0) + 1;
      }
    }
    final latest = [...articles]..sort((a, b) => b.date.compareTo(a.date));
    recent = latest.take(5).expand(values).toSet().toList();
    popular = counts.keys.toList()
      ..sort((a, b) {
        final count = counts[b]!.compareTo(counts[a]!);
        return count == 0 ? a.compareTo(b) : count;
      });
  }
  final counts = <String, int>{};
  late final List<String> recent, popular;
}

class TaxonomySuggestions {
  TaxonomySuggestions(
    TaxonomyCatalog catalog,
    Iterable<String> pins,
    Iterable<String> selected,
  ) {
    final excluded = selected.toSet();
    List<String> take(Iterable<String> source, int count) {
      final list = source
          .where((s) => !excluded.contains(s))
          .take(count)
          .toList();
      excluded.addAll(list);
      return list;
    }

    pinned = take(pins, 4);
    recent = take(catalog.recent, 3);
    popular = take(catalog.popular, 3);
  }
  late final List<String> pinned, recent, popular;
}
