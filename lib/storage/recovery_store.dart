import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'package:blog_studio/models/article.dart';
import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/storage/front_matter_codec.dart';

class RecoveryRecord {
  const RecoveryRecord(
    this.original,
    this.body,
    this.attributes,
    this.updatedAt,
  );
  final ArticleSnapshot original;
  final String body;
  final Map<String, dynamic> attributes;
  final DateTime updatedAt;
  String get path => original.relativePath;
  String get title => attributes['title']?.toString() ?? original.title;
}

/// A separate durable journal: restoring never overwrites a changed original.
class RecoveryStore {
  RecoveryStore(this.store);
  final FileStore store;
  final Map<String, String> errors = {};
  static String _recordPath(String path) =>
      '.blog-studio/recovery/${contentHash(utf8.encode(path))}.json';

  Future<void> checkpoint(RecoveryRecord record) async {
    final path = _recordPath(record.path);
    final file = File(await store.guard.resolve(path));
    final hash = await file.exists()
        ? contentHash(await file.readAsBytes())
        : null;
    await store.write(
      path,
      utf8.encode(
        jsonEncode({
          'formatVersion': 1,
          'path': record.path,
          'original': base64Encode(record.original.originalBytes),
          'body': record.body,
          'attributes': record.attributes,
          'updatedAt': record.updatedAt.toIso8601String(),
        }),
      ),
      expectedHash: hash,
    );
  }

  Future<List<RecoveryRecord>> list() async {
    final root = Directory(await store.guard.resolve('.blog-studio/recovery'));
    if (!await root.exists()) return [];
    final records = <RecoveryRecord>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final recordPath = '.blog-studio/recovery/${p.basename(entity.path)}';
      try {
        final data =
            jsonDecode(utf8.decode(await store.read(recordPath))) as Map;
        final path = data['path'] as String;
        if (data['formatVersion'] != 1 ||
            !(path == 'resource/about.md' ||
                RegExp(
                  r'^resource/(posts|drafts|notes)/.+\.md$',
                  caseSensitive: false,
                ).hasMatch(path))) {
          throw const FormatException('恢复记录格式无效，请保留恢复目录中的文件。');
        }
        await store.guard.resolve(path);
        if (recordPath != _recordPath(path)) {
          throw const FormatException('恢复记录路径不匹配。');
        }
        final bytes = Uint8List.fromList(
          base64Decode(data['original'] as String),
        );
        final doc = FrontMatterDocument.parse(utf8.decode(bytes));
        records.add(
          RecoveryRecord(
            ArticleSnapshot(
              relativePath: path,
              originalBytes: bytes,
              contentHash: contentHash(bytes),
              frontMatter: doc.fields,
              bodySource: doc.body,
            ),
            data['body'] as String,
            Map<String, dynamic>.from(data['attributes'] as Map),
            DateTime.parse(data['updatedAt'] as String),
          ),
        );
      } catch (e) {
        errors[p.basename(entity.path)] = '$e';
      }
    }
    records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return records;
  }

  Future<void> clear(
    String path,
    String body,
    Map<String, dynamic> attributes,
  ) => store.serial(() async {
    final file = File(await store.guard.resolve(_recordPath(path)));
    if (!await file.exists()) return;
    final data = jsonDecode(await file.readAsString()) as Map;
    // A later keystroke may already have queued a newer journal entry.
    if (data['body'] == body &&
        jsonEncode(data['attributes']) == jsonEncode(attributes)) {
      await file.delete();
    }
  });
}
