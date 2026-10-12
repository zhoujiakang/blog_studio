import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/storage/article_repository.dart';
import 'package:blog_studio/storage/trash_repository.dart';
import 'package:blog_studio/storage/recovery_store.dart';
import 'package:blog_studio/models/trash_entry.dart';

void main() {
  test(
    'permanent deletion removes one entry and orphaned backups, keeps images',
    () async {
      final root = await Directory.systemTemp.createTemp('inkjian-purge-');
      try {
        final repo = ArticleRepository(root.path);
        var article = await repo.create('待删除');
        article = await repo.save(article, '第一版', {});
        article = await repo.save(article, '第二版', {});
        final recovery = RecoveryStore(repo.store);
        await recovery.checkpoint(
          RecoveryRecord(article, '未保存内容', article.frontMatter, DateTime.now()),
        );
        final image = File('${root.path}/resource/images/shared.png');
        await image.parent.create(recursive: true);
        await image.writeAsBytes([1, 2, 3]);
        final trash = TrashRepository(repo.store);
        await trash.remove(article);
        final other = await repo.create('保留的回收文章');
        await trash.remove(other);
        final entry = (await trash.list()).firstWhere(
          (item) => item.originalPath == article.relativePath,
        );
        await trash.deletePermanently(entry);
        expect((await trash.list()).single.originalPath, other.relativePath);
        expect(
          await Directory('${root.path}/.blog-studio/trash/${entry.id}')
              .exists(),
          false,
        );
        expect(
          await File(
            '${root.path}/.blog-studio/backups/${article.relativePath}',
          ).exists(),
          false,
        );
        expect(await recovery.list(), isEmpty);
        expect(await image.readAsBytes(), [1, 2, 3]);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
  test('changed trash bytes reject deletion before removing backups', () async {
    final root = await Directory.systemTemp.createTemp(
      'inkjian-purge-conflict-',
    );
    try {
      final repo = ArticleRepository(root.path);
      var article = await repo.create('外部修改');
      article = await repo.save(article, '原正文', {});
      final backup = File(
        '${root.path}/.blog-studio/backups/${article.relativePath}',
      );
      final trash = TrashRepository(repo.store);
      await trash.remove(article);
      final entry = (await trash.list()).single;
      final file = File(
        '${root.path}/.blog-studio/trash/${entry.id}/article.md',
      );
      await file.writeAsString('外部版本');
      await expectLater(trash.deletePermanently(entry), throwsA(anything));
      expect(await file.readAsString(), '外部版本');
      expect(await backup.exists(), true);
    } finally {
      await root.delete(recursive: true);
    }
  });
  test('a restored or forged entry cannot delete current files', () async {
    final root = await Directory.systemTemp.createTemp('inkjian-purge-stale-');
    try {
      final repo = ArticleRepository(root.path);
      final article = await repo.create('已恢复');
      final trash = TrashRepository(repo.store);
      await trash.remove(article);
      final entry = (await trash.list()).single;
      await trash.restore(entry);
      await expectLater(trash.deletePermanently(entry), throwsA(anything));
      final forged = TrashEntry(
        id: '../resource',
        originalPath: entry.originalPath,
        contentHash: entry.contentHash,
        title: entry.title,
        deletedAt: entry.deletedAt,
      );
      await expectLater(trash.deletePermanently(forged), throwsA(anything));
      expect(
        (await repo.read(article.relativePath)).originalBytes,
        article.originalBytes,
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
  test(
    'a new document at the same path retains its content and backup',
    () async {
      final root = await Directory.systemTemp.createTemp('inkjian-purge-new-');
      try {
        final repo = ArticleRepository(root.path);
        final article = await repo.create('旧文档');
        final trash = TrashRepository(repo.store);
        await trash.remove(article);
        final entry = (await trash.list()).single;
        final current = File('${root.path}/${article.relativePath}');
        await current.writeAsString('新的文档');
        final backup = File(
          '${root.path}/.blog-studio/backups/${article.relativePath}',
        );
        await backup.parent.create(recursive: true);
        await backup.writeAsString('新的备份');
        await trash.deletePermanently(entry);
        expect(await current.readAsString(), '新的文档');
        expect(await backup.readAsString(), '新的备份');
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
  test('another recycled generation keeps the shared backup', () async {
    final root = await Directory.systemTemp.createTemp('inkjian-purge-shared-');
    try {
      final repo = ArticleRepository(root.path);
      final article = await repo.create('第一代');
      final trash = TrashRepository(repo.store);
      await trash.remove(article);
      final entry = (await trash.list()).single;
      await File('${root.path}/${article.relativePath}').writeAsString('第二代');
      final next = await repo.read(article.relativePath);
      await trash.remove(next);
      final backup = File(
        '${root.path}/.blog-studio/backups/${article.relativePath}',
      );
      await backup.parent.create(recursive: true);
      await backup.writeAsString('共享备份');
      await trash.deletePermanently(entry);
      expect((await trash.list()).single.contentHash, next.contentHash);
      expect(await backup.readAsString(), '共享备份');
    } finally {
      await root.delete(recursive: true);
    }
  });
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
