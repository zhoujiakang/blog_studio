import 'package:blog_studio/models/article_metadata.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'package:blog_studio/models/article.dart';
import 'package:blog_studio/models/markdown_path.dart';
import 'package:blog_studio/storage/resource_layout.dart';
import 'package:blog_studio/models/studio_exception.dart';
import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/storage/front_matter_codec.dart';
import 'package:blog_studio/storage/path_guard.dart';

class ArticleRepository {
  ArticleRepository(String root) : store = FileStore(PathGuard(root));
  final FileStore store;
  ResourceLayout get layout => ResourceLayout(store.guard.root);
  Future<ArticleSnapshot> read(String relative) async {
    _validateArticle(relative);
    final bytes = await store.read(relative);
    final document = FrontMatterDocument.parse(utf8.decode(bytes));
    ArticleMetadata.validate(document.fields);
    return ArticleSnapshot(
      relativePath: relative,
      originalBytes: bytes,
      contentHash: contentHash(bytes),
      frontMatter: document.fields,
      bodySource: document.body,
    );
  }

  Future<ArticleIndex> scan({bool notes = false}) async {
    final articles = <ArticleSummary>[];
    final errors = <String, String>{};
    for (final dir in notes ? [layout.notes] : [layout.posts, layout.drafts]) {
      try {
        final directory = Directory(await store.guard.resolve(dir));
        if (!await directory.exists()) continue;
        await for (final file in directory.list(
          recursive: true,
          followLinks: false,
        )) {
          final relative = p
              .relative(
                file.path,
                from: await Directory(store.guard.root).resolveSymbolicLinks(),
              )
              .replaceAll(p.separator, '/');
          if (file is! File ||
              !isMarkdownPath(file.path) ||
              relative.split('/').any((s) => s.startsWith('.'))) {
            continue;
          }
          try {
            final article = await read(relative);
            articles.add(ArticleSummary.fromSnapshot(article));
          } catch (e) {
            errors[relative] = '$e';
          }
        }
      } catch (e) {
        errors[dir] = '$e';
      }
    }
    articles.sort((a, b) => b.date.compareTo(a.date));
    return ArticleIndex(articles, errors: errors);
  }

  static List<String> values(dynamic value) => ArticleSummary.values(value);
  Future<ArticleSnapshot> create(String title) async {
    final id = DateTime.now().microsecondsSinceEpoch;
    final date = DateTime.now()
        .toIso8601String()
        .substring(0, 19)
        .replaceAll('T', ' ');
    final relative = '${layout.drafts}/post-$id.md';
    final source =
        '---\ntitle: ${jsonEncode(title.trim().isEmpty ? '未命名文章' : title.trim())}\ndate: "$date"\ntags: []\ncategories: []\n---\n\n';
    await store.write(relative, utf8.encode(source), expectedHash: null);
    return read(relative);
  }

  Future<ArticleSnapshot> openAbout() async {
    final path = layout.about;
    if (!await File(await store.guard.resolve(path)).exists()) {
      await store.write(path, utf8.encode('# 关于\n\n'), expectedHash: null);
    }
    return read(path);
  }

  Future<ArticleSnapshot> createNote() async {
    final now = DateTime.now();
    final date = now.toIso8601String().substring(0, 19).replaceAll('T', ' ');
    final relative =
        '${layout.notes}/${date.substring(0, 10)}/note-${now.microsecondsSinceEpoch}.md';
    await store.write(
      relative,
      utf8.encode('---\ndate: "$date"\nupdated: "$date"\n---\n\n'),
      expectedHash: null,
    );
    return read(relative);
  }

  Future<ArticleSnapshot> save(
    ArticleSnapshot original,
    String body,
    Map<String, dynamic> changes,
  ) async {
    ArticleMetadata.validate({...original.frontMatter, ...changes});
    final document = FrontMatterDocument.parse(
      utf8.decode(original.originalBytes),
    );
    final bytes = utf8.encode(
      document.encode(body, {
        ...changes,
        if (original.note)
          'updated': DateTime.now()
              .toIso8601String()
              .substring(0, 19)
              .replaceAll('T', ' '),
      }),
    );
    final hash = await store.write(
      original.relativePath,
      bytes,
      expectedHash: original.contentHash,
    );
    final parsed = FrontMatterDocument.parse(utf8.decode(bytes));
    return ArticleSnapshot(
      relativePath: original.relativePath,
      originalBytes: Uint8List.fromList(bytes),
      contentHash: hash,
      frontMatter: parsed.fields,
      bodySource: parsed.body,
    );
  }

  Future<ArticleSnapshot> setDraft(ArticleSnapshot original, bool draft) async {
    if (!original.post) {
      throw const StudioException(StudioError.invalidProject, '小记不能转为草稿或正式文章。');
    }
    final target = original.relativePath.replaceFirst(
      RegExp(r'^resource/(posts|drafts)/'),
      '${draft ? layout.drafts : layout.posts}/',
    );
    if (target != original.relativePath &&
        await File(await store.guard.resolve(target)).exists()) {
      throw const StudioException(StudioError.fileConflict, '目标已有同名文章，未覆盖。');
    }
    final updated = await save(original, original.bodySource, {
      if (original.frontMatter.containsKey('draft')) 'draft': draft,
      if (original.frontMatter.containsKey('published')) 'published': !draft,
    });
    if (target != original.relativePath) {
      await store.move(original.relativePath, target, updated.contentHash!);
    }
    return read(target);
  }

  void _validateArticle(String relative) {
    if (relative == layout.about) return;
    if (!RegExp(
      r'^resource/(posts|drafts|notes)/.+\.md$',
      caseSensitive: false,
    ).hasMatch(relative)) {
      throw const StudioException(
        StudioError.invalidProject,
        '仅能编辑文章、草稿和小记中的 Markdown 文件。',
      );
    }
  }
}
