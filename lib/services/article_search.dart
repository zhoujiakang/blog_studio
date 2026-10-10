import 'package:blog_studio/models/article.dart';

String categoryPath(String value) =>
    value.split('/').map((s) => s.trim()).where((s) => s.isNotEmpty).join('/');

bool matchesArticle(
  ArticleSummary article, {
  String query = '',
  String? tag,
  String? category,
}) {
  if (tag != null && !article.tags.contains(tag)) return false;
  if (category != null) {
    final paths = article.categories
        .map(categoryPath)
        .where((s) => s.isNotEmpty)
        .toList();
    if (category.isEmpty
        ? paths.isNotEmpty
        : !paths.any((p) => p == category || p.startsWith('$category/'))) {
      return false;
    }
  }
  final text =
      '${article.title}\n${article.searchText}\n${article.tags.join(' ')}\n${article.categories.join(' ')}'
          .toLowerCase();
  return query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .every(text.contains);
}

class CategoryNode {
  CategoryNode(this.name, this.path);
  final String name, path;
  final Map<String, CategoryNode> children = {};
  final Set<String> articles = {};
  bool containsQuery(String query) =>
      name.toLowerCase().contains(query) ||
      path.toLowerCase().contains(query) ||
      children.values.any((n) => n.containsQuery(query));
  List<CategoryNode> get sorted =>
      children.values.toList()..sort((a, b) => a.name.compareTo(b.name));
}

class ArticleFacets {
  ArticleFacets(List<ArticleSummary> articles) {
    for (final article in articles) {
      for (final tag in article.tags.toSet()) {
        tags.update(tag, (count) => count + 1, ifAbsent: () => 1);
      }
      final paths = article.categories
          .map(categoryPath)
          .where((s) => s.isNotEmpty)
          .toSet();
      if (paths.isEmpty) uncategorized++;
      for (final path in paths) {
        var parent = root;
        var prefix = '';
        for (final segment in path.split('/')) {
          prefix = prefix.isEmpty ? segment : '$prefix/$segment';
          parent = parent.children.putIfAbsent(
            segment,
            () => CategoryNode(segment, prefix),
          );
          parent.articles.add(article.relativePath);
        }
      }
    }
  }
  final CategoryNode root = CategoryNode('', '');
  final Map<String, int> tags = {};
  int uncategorized = 0;
}

class LibraryResults {
  LibraryResults({
    required ArticleIndex index,
    required ArticleIndex notes,
    required String section,
    required String search,
    String? tag,
    String? category,
  }) {
    query = search.trim().toLowerCase();
    isNotes = section == 'notes';
    final source = isNotes ? notes : index;
    errors = source.errors;
    pool = source.articles
        .where((a) => section != 'drafts' || a.draft)
        .toList();
    articles = pool
        .where(
          (a) => isNotes
              ? a.searchText.toLowerCase().contains(query)
              : matchesArticle(a, query: query, tag: tag, category: category),
        )
        .toList();
  }
  late final String query;
  late final bool isNotes;
  late final List<ArticleSummary> pool, articles;
  late final Map<String, String> errors;
}
