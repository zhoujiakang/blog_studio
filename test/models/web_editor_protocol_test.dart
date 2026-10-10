import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/models/web_editor_protocol.dart';

void main() {
  test('late events cannot overwrite another article or newer revision', () {
    final protocol = WebEditorProtocol()..open('new', '中文');
    String event(String session, int revision, String markdown) => jsonEncode({
      'protocol': 1,
      'type': 'change',
      'session': session,
      'revision': revision,
      'markdown': markdown,
      'composing': false,
    });
    expect(protocol.accept(event('old', 20, '旧文章')), isNull);
    expect(protocol.accept(event('new', 2, '**重点**')), isNotNull);
    expect(protocol.accept(event('new', 1, '过期输入')), isNull);
    expect(protocol.markdown, '**重点**');
  });
  test('malformed messages leave source untouched', () {
    final protocol = WebEditorProtocol()..open('one', '<!-- more -->');
    for (final invalid in [
      '{',
      '[]',
      '{"protocol":2}',
      '{"protocol":1,"session":"one","type":"change","revision":"2"}',
    ]) {
      expect(protocol.accept(invalid), isNull);
    }
    expect(protocol.markdown, '<!-- more -->');
  });
}
