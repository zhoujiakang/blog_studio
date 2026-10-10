import 'package:blog_studio/models/article_metadata.dart';

import 'dart:typed_data';

class ArticleSnapshot {
  const ArticleSnapshot({
    required this.relativePath,
    required this.originalBytes,
    required this.contentHash,
    required this.frontMatter,
    required this.bodySource,
    this.revision = 0,
  });
  final String relativePath;
  final Uint8List originalBytes;
  final String? contentHash;
  final Map<String, dynamic> frontMatter;
  final String bodySource;
  final int revision;
  bool get note => relativePath.startsWith('resource/notes/');
  bool get about => relativePath == 'resource/about.md';
  bool get post => !note && !about;
  String get title {
    if (about) return '关于';
    if (!note) return frontMatter['title']?.toString() ?? '未命名文章';
    final lines = bodySource
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    if (lines.isEmpty) return '空白小记';
    final first = lines.first.replaceFirst(RegExp(r'^#{1,6}\s+'), '');
    return first.length > 60 ? '${first.substring(0, 60)}…' : first;
  }

  bool get draft =>
      relativePath.startsWith('resource/drafts/') ||
      frontMatter['draft'] == true ||
      frontMatter['published'] == false;
}

class ArticleSummary {
  const ArticleSummary({
    required this.relativePath,
    required this.title,
    required this.date,
    required this.draft,
    required this.searchText,
    this.tags = const [],
    this.categories = const [],
  });
  factory ArticleSummary.fromSnapshot(ArticleSnapshot article) =>
      ArticleSummary(
        relativePath: article.relativePath,
        title: article.title,
        date: article.frontMatter['date']?.toString() ?? '',
        draft: article.draft,
        searchText: '${article.title}\n${article.bodySource}',
        tags: values(article.frontMatter['tags']),
        categories: values(article.frontMatter['categories']),
      );

  static List<String> values(dynamic value) => ArticleMetadata.values(value);

  final String relativePath, title, date, searchText;
  bool get note => relativePath.startsWith('resource/notes/');
  final bool draft;
  final List<String> tags, categories;
}

class ArticleIndex {
  const ArticleIndex(this.articles, {this.errors = const {}});
  final List<ArticleSummary> articles;
  final Map<String, String> errors;
  List<String> get tags =>
      (articles.expand((a) => a.tags).toSet().toList()..sort());
  List<String> get categories =>
      (articles.expand((a) => a.categories).toSet().toList()..sort());
}
