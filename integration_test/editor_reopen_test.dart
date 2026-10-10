import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support.dart';

import 'package:blog_studio/ui/pages/studio_home.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('diagnose editor reopening after returning to library', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('studio-reopen-repro-');
    final session = nativeTestSession();
    final observations = <Map<String, dynamic>>[];
    try {
      expect(await session.openProject(root.path, initialize: true), true);
      expect(await session.createArticle('重复打开复现'), true);
      final path = session.article!.relativePath;
      await tester.pumpWidget(MaterialApp(home: StudioHome(session: session)));
      for (var attempt = 0; attempt < 4; attempt++) {
        Map<String, dynamic>? state;
        for (var tick = 0; tick < 100; tick++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (session.nativeEditor.error != null) break;
          if (session.nativeEditor.ready) {
            try {
              state = await session.nativeEditor.inspect();
              if (state['session'] == session.nativeEditor.protocol.session) {
                break;
              }
              state = null;
            } catch (_) {}
          }
        }
        final observation = <String, dynamic>{
          'attempt': attempt,
          'ready': session.nativeEditor.ready,
          'error': session.nativeEditor.error,
          'session': session.nativeEditor.protocol.session,
          'document': state,
          'native': await session.nativeEditor.nativeFocusState(),
        };
        observations.add(observation);
        debugPrint('REOPEN: ${jsonEncode(observation)}');
        expect(state, isNotNull, reason: 'attempt $attempt must load');
        expect(
          (observation['native'] as Map)['pointerReachesEditor'],
          true,
          reason: 'the drag overlay must not intercept the editor mouse target',
        );
        await session.nativeEditor.evaluate(
          "document.querySelector('.ProseMirror').focus(); document.execCommand('insertText', false, '第$attempt轮输入'); true",
        );
        await tester.pump(const Duration(milliseconds: 300));
        observation['afterInput'] = await session.nativeEditor.serialize();
        expect(observation['afterInput'], contains('第$attempt轮输入'));
        expect(await session.flush(), true);
        expect(await session.closeArticle(), true);
        await tester.pumpAndSettle();
        expect(find.text('文章'), findsWidgets);
        if (attempt < 3) {
          expect(await session.openArticle(path), true);
          await tester.pump();
        }
      }
    } finally {
      final output = Directory('build/verification')
        ..createSync(recursive: true);
      File('${output.path}/editor-reopen-repro.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(observations),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      session.dispose();
      await root.delete(recursive: true);
    }
  });
}
