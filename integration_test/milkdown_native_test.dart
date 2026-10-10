import 'package:blog_studio/controllers/web_markdown_controller.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:blog_studio/ui/components/web_markdown_editor.dart';
import 'package:blog_studio/models/image.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('bundled Milkdown parses and retains source inside macOS WKWebView', (
    tester,
  ) async {
    final controller = WebMarkdownController();
    const source =
        '# 中文标题\r\n\r\n**重点**\r\n\r\n<!-- more -->\r\n\r\n```js\r\n# literal\r\n```\r\n';
    await controller.open(source);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WebMarkdownEditor(controller: controller)),
      ),
    );
    Map<String, dynamic>? state;
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (controller.error != null) fail(controller.error!);
      if (controller.ready) {
        try {
          state = await controller.inspect();
          break;
        } catch (_) {
          /* JS creation is async. */
        }
      }
    }
    if (state == null) {
      debugPrint(
        'WebView diagnostic: ${await controller.evaluate("JSON.stringify({url:location.href,ready:document.readyState,studio:typeof window.studio,htmlLength:document.body.innerHTML.length})")}',
      );
    }
    expect(
      state,
      isNotNull,
      reason: 'local editor must load and finish creating its document',
    );
    expect(state!['markdown'], source);
    // DOM focus alone is insufficient: keyboard events need an AppKit responder.
    expect(await controller.focus(), true);
    expect((await controller.nativeFocusState())!['editorFocused'], true);
    await controller.blurForTest();
    expect((await controller.nativeFocusState())!['editorFocused'], false);
    final released = await controller.nativeFocusState();
    await controller.blurForTest();
    expect(
      (await controller.nativeFocusState())!['firstResponder'],
      released!['firstResponder'],
    );
    expect(await controller.focus(), true);
    expect((await controller.nativeFocusState())!['editorFocused'], true);
    final nodes = (state['document'] as Map)['content'] as List;
    expect(nodes[0]['type'], 'heading');
    expect(nodes[0]['content'][0]['text'], '中文标题');
    expect(nodes[1]['content'][0]['marks'][0]['type'], 'strong');
    expect(nodes[2]['type'], 'studio_preserved');
    expect(nodes[2]['attrs']['source'], '<!-- more -->');
    expect(nodes[3]['type'], 'code_block');
    expect(await controller.serialize(), source);
    final pixel = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
    );
    await controller.insertImage(
      ImportedImage(
        relativeAssetPath: 'public/img/test.png',
        markdownUrl: '/img/test.png',
        mediaType: 'image/png',
        byteLength: pixel.length,
        imageId: 'test',
      ),
      pixel,
    );
    await tester.pump(const Duration(milliseconds: 500));
    final withImage = await controller.serialize();
    expect(withImage, contains('/img/test.png'));
    expect(withImage, isNot(contains('data:image')));
    expect(
      await controller.evaluate(
        "Array.from(document.images).some(image => image.src.startsWith('data:image/png'))",
      ),
      true,
    );
    await controller.command('undo');
    await tester.pump(const Duration(milliseconds: 500));
    expect(await controller.serialize(), source);
    // Change one actual DOM paragraph. Preserve neighboring source fragments.
    await controller.evaluate('''(() => {
      const paragraph = document.querySelector('.ProseMirror p');
      const range = document.createRange(); range.selectNodeContents(paragraph);
      const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
      paragraph.closest('[contenteditable]').focus();
      document.execCommand('insertText', false, '修改正文'); return true;
    })()''');
    await tester.pump(const Duration(milliseconds: 500));
    final changed = await controller.serialize();
    expect(changed, contains('# 中文标题\r\n\r\n'));
    expect(changed, contains('修改正文'));
    expect(changed, contains('<!-- more -->'));
    expect(changed, contains('```js\r\n# literal\r\n```'));
    await controller.command('undo');
    await tester.pump(const Duration(milliseconds: 500));
    expect(await controller.serialize(), source);
    final output = Directory('build/verification')..createSync(recursive: true);
    File('${output.path}/milkdown-native-state.json')
        .writeAsStringSync(jsonEncode(state));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    controller.dispose();
  });
}
