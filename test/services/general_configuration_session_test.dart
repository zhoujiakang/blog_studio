import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/storage/path_guard.dart';
import 'package:blog_studio/services/general_configuration_session.dart';
import 'package:blog_studio/storage/blog_configuration.dart';

class SlowConfigurationStore extends FileStore {
  SlowConfigurationStore(super.guard);
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<String> write(
    String relative,
    List<int> bytes, {
    required String? expectedHash,
  }) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return super.write(relative, bytes, expectedHash: expectedHash);
  }
}

void main() {
  test('editing common settings during save keeps newer changes and template selection', () async {
    final root = await Directory.systemTemp.createTemp('inkjian-general-race-');
    final store = SlowConfigurationStore(PathGuard(root.path));
    final document = {
      'formatVersion': 2,
      'activeTemplate': 'butterfly',
      'site': {'title': '原始', 'custom': '保留'},
    };
    final bytes = utf8.encode(jsonEncode(document));
    await File('${root.path}/blog.json').writeAsBytes(bytes);
    final session = GeneralConfigurationSession()
      ..load(BlogConfiguration(document, contentHash(bytes)));
    try {
      session.change('title', '第一版');
      final saving = session.save(store);
      await store.entered.future;
      session.change('title', '写入期间的中文修改');
      store.release.complete();
      await saving;
      expect(session.dirty, true);
      expect(session.configuration!.site['title'], '写入期间的中文修改');
      await session.save(store);
      final saved = jsonDecode(
        await File('${root.path}/blog.json').readAsString(),
      );
      expect(saved['site']['title'], '写入期间的中文修改');
      expect(saved['site']['custom'], '保留');
      expect(saved['activeTemplate'], 'butterfly');
      expect(session.dirty, false);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
