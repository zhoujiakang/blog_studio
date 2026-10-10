import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/storage/path_guard.dart';
import 'package:blog_studio/services/template_settings_session.dart';
import 'package:blog_studio/storage/template_configuration.dart';

class GatedStore extends FileStore {
  GatedStore(super.guard);
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
  test('configuration edited during save retains newer values and uses updated disk hash', () async {
    final root = await Directory.systemTemp.createTemp('studio-settings-race-');
    final doc = {
      'formatVersion': 1,
      'id': 'butterfly',
      'name': 'Butterfly',
      'fields': [
        {
          'key': 'announcement',
          'label': '公告',
          'type': 'text',
          'default': '',
          'value': '原始',
        },
      ],
    };
    final bytes = utf8.encode(jsonEncode(doc));
    await File('${root.path}/template.json').writeAsBytes(bytes);
    final state = TemplateSettingsSession()
      ..load(TemplateConfiguration('template.json', doc, contentHash(bytes)));
    final store = GatedStore(PathGuard(root.path));
    try {
      state.change('announcement', '第一版');
      final saving = state.save(store);
      await store.entered.future;
      state.change('announcement', '保存期间的新版本');
      store.release.complete();
      await saving;
      expect(state.dirty, true);
      expect(
        state.configuration!.value(state.configuration!.fields.single),
        '保存期间的新版本',
      );
      await state.save(store);
      expect(state.dirty, false);
      final saved = jsonDecode(
        await File('${root.path}/template.json').readAsString(),
      );
      expect(saved['fields'][0]['value'], '保存期间的新版本');
    } finally {
      await root.delete(recursive: true);
    }
  });
}
