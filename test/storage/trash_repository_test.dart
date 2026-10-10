import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/storage/article_repository.dart';
import 'package:blog_studio/storage/trash_repository.dart';

void main() {
  for (final damage in ['json', 'missing', 'date', 'path', 'type']) {
    test(
      'damaged $damage record does not block healthy trash recovery',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'inkjian-trash-damage-',
        );
        try {
          final repo = ArticleRepository(root.path);
          final trash = TrashRepository(repo.store);
          final good = await repo.create('可恢复');
          await trash.remove(good);
          final bad = await repo.create('损坏记录');
          await trash.remove(bad);
          final entries = await trash.list();
          final damaged = entries.firstWhere(
            (e) => e.originalPath == bad.relativePath,
          );
          final recordFile = File(
            '${root.path}/.blog-studio/trash/${damaged.id}/record.json',
          );
          final record = jsonDecode(await recordFile.readAsString()) as Map;
          if (damage == 'missing') {
            await recordFile.delete();
          } else if (damage == 'json') {
            await recordFile.writeAsString('{bad');
          } else {
            if (damage == 'date') record['deletedAt'] = 'invalid';
            if (damage == 'path') record['originalPath'] = '../outside.md';
            if (damage == 'type') record['title'] = 7;
            await recordFile.writeAsString(jsonEncode(record));
          }
          final listing = await trash.scan();
          expect(listing.entries.single.originalPath, good.relativePath);
          expect(listing.errors.keys, [damaged.id]);
          expect((await trash.list()).length, 1);
          await trash.restore(listing.entries.single);
          expect(
            (await repo.read(good.relativePath)).originalBytes,
            good.originalBytes,
          );
          expect(
            await File(
              '${root.path}/.blog-studio/trash/${damaged.id}/article.md',
            ).readAsBytes(),
            bad.originalBytes,
          );
          expect((await trash.scan()).errors.keys, [damaged.id]);
        } finally {
          await root.delete(recursive: true);
        }
      },
    );
  }
}
