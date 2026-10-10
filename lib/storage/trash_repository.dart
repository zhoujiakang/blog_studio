import 'dart:convert';
import 'dart:io';

import 'package:blog_studio/models/article.dart';
import 'package:blog_studio/models/trash_entry.dart';
import 'package:blog_studio/models/studio_exception.dart';
import 'package:blog_studio/storage/file_store.dart';

class TrashRepository {
  TrashRepository(this.store);
  final FileStore store;
  Future<void> remove(ArticleSnapshot article) async {
    if (article.about) throw const FormatException('关于页面不能移入文章回收区。');
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final base = '.blog-studio/trash/$id';
    final record = {
      'id': id,
      'originalPath': article.relativePath,
      'deletedAt': DateTime.now().toIso8601String(),
      'contentHash': article.contentHash,
      'title': article.title,
    };
    await store.write(
      '$base/record.json',
      utf8.encode(jsonEncode(record)),
      expectedHash: null,
    );
    // The record is durable before moving the original. An interrupted move
    // with data present remains discoverable without relying on a status flag.
    await store.move(
      article.relativePath,
      '$base/article.md',
      article.contentHash!,
    );
  }

  Future<List<TrashEntry>> list() async => (await scan()).entries;

  Future<TrashListing> scan() async {
    final root = Directory(await store.guard.resolve('.blog-studio/trash'));
    if (!await root.exists()) return const TrashListing([]);
    final records = <TrashEntry>[];
    final errors = <String, String>{};
    await for (final dir in root.list(followLinks: false)) {
      if (dir is! Directory) continue;
      final id = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (!RegExp(r'^\d+$').hasMatch(id)) continue;
      final base = '.blog-studio/trash/$id';
      try {
        if (!await File(await store.guard.resolve('$base/article.md'))
            .exists()) {
          continue;
        }
        final record = jsonDecode(
          utf8.decode(await store.read('$base/record.json')),
        );
        if (record is! Map ||
            record['id'] != id ||
            record['originalPath'] is! String ||
            record['deletedAt'] is! String ||
            record['contentHash'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(record['contentHash']) ||
            record['title'] is! String) {
          throw const FormatException('回收记录格式无效。');
        }
        await store.guard.resolve(record['originalPath']);
        records.add(
          TrashEntry(
            id: id,
            originalPath: record['originalPath'],
            deletedAt: DateTime.parse(record['deletedAt']),
            contentHash: record['contentHash'],
            title: record['title'],
          ),
        );
      } catch (e) {
        // Keep damaged records and article bytes intact for manual recovery.
        errors[id] = '$e';
      }
    }
    records.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return TrashListing(records, errors: errors);
  }

  Future<void> restore(TrashEntry entry) async {
    if (!RegExp(r'^\d+$').hasMatch(entry.id) ||
        !RegExp(r'^resource/(posts|drafts|notes)/.+\.md$')
            .hasMatch(entry.originalPath)) {
      throw const StudioException(StudioError.invalidProject, '回收记录的路径不合法。');
    }
    await store.move(
      '.blog-studio/trash/${entry.id}/article.md',
      entry.originalPath,
      entry.contentHash,
    );
    // Keep the record as an audit entry; the absent data hides it from the list.
  }
}
