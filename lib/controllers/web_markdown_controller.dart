import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:blog_studio/models/document_editor.dart';
import 'package:blog_studio/platform/contracts/desktop_platform.dart';
import 'package:blog_studio/models/web_editor_protocol.dart';
import 'package:blog_studio/models/image.dart';

class WebMarkdownController extends DocumentEditor {
  final protocol = WebEditorProtocol();
  @override
  String get documentId => protocol.session;

  Future<bool> focus() async {
    final focused = await _web?.focus() ?? false;
    if (focused) await _send({'type': 'focus', 'session': protocol.session});
    return focused;
  }

  @visibleForTesting
  Future<Map<dynamic, dynamic>?> nativeFocusState() =>
      Future.value(_web?.focusState());

  @override
  Future<void> releaseKeyboard() => _web?.releaseKeyboard() ?? Future.value();

  @visibleForTesting
  Future<void> blurForTest() => releaseKeyboard();
  EditorHost? _web;
  bool isAttachedTo(EditorHost host) => identical(_web, host);
  void attachHost(EditorHost host) {
    _web = host;
    ready = false;
  }

  void detachHost(EditorHost host) {
    if (isAttachedTo(host)) {
      _web = null;
      ready = false;
    }
  }

  bool ready = false;
  @override
  String? error;
  @override
  VoidCallback? onSave;
  @override
  VoidCallback? onPasteImage;
  Map<String, String> _images = {};
  int _sessionNumber = 0;
  int _requestNumber = 0;
  final _snapshots = <int, Completer<String>>{};

  @override
  String get markdown => protocol.markdown;
  int get revision => protocol.revision;
  @override
  bool get composing => protocol.composing;

  void reportError(String message) {
    error = message;
    notifyListeners();
  }

  @visibleForTesting
  Future<Map<String, dynamic>> inspect() async {
    final result = await _web!.evaluate(
      'JSON.stringify(window.studio.inspect())',
    );
    return jsonDecode(result as String) as Map<String, dynamic>;
  }

  @visibleForTesting
  Future<Object> evaluate(String script) => _web!.evaluate(script);

  @override
  Future<void> open(
    String source, {
    Map<String, String> images = const {},
  }) async {
    _images = images;
    protocol.open('document-${++_sessionNumber}', source);
    error = null;
    if (ready) await _openInView();
    notifyListeners();
  }

  Future<void> _openInView() => _send({
    'type': 'open',
    'session': protocol.session,
    'revision': protocol.revision,
    'markdown': markdown,
    'images': _images,
  });

  @override
  Future<void> command(String type) =>
      _send({'type': type, 'session': protocol.session});

  @override
  Future<void> bookmarkImageSelection() => command('bookmarkImage');

  @override
  Future<void> insertImage(ImportedImage image, Uint8List bytes) => _send({
    'type': 'image',
    'session': protocol.session,
    'url': image.markdownUrl,
    'data': 'data:${image.mediaType};base64,${base64Encode(bytes)}',
  });

  @override
  Future<void> insertMarkdown(
    String markdown, {
    Map<String, String> images = const {},
  }) => _send({
    'type': 'insertMarkdown',
    'session': protocol.session,
    'markdown': markdown,
    'images': images,
  });

  @override
  Future<String> serialize() async {
    if (!ready) throw StateError('编辑器尚未准备完成');
    final request = ++_requestNumber;
    final result = Completer<String>();
    _snapshots[request] = result;
    try {
      await _send({
        'type': 'snapshot',
        'session': protocol.session,
        'request': request,
      });
      return await result.future.timeout(const Duration(seconds: 5));
    } finally {
      _snapshots.remove(request);
    }
  }

  Future<void> _send(Map<String, dynamic> message) async {
    await _web?.execute('window.studio.receive(${jsonEncode(message)})');
  }

  void receive(String message) {
    if (_web == null) return;
    final event = protocol.accept(message);
    if (event == null) return;
    if (event['type'] == 'ready') {
      ready = true;
      unawaited(_openInView());
    }
    if (event['type'] == 'pasteImage') onPasteImage?.call();
    if (event['type'] == 'save' && !composing) onSave?.call();
    if (event['type'] == 'opened') unawaited(focus());
    if (event['type'] == 'error') error = event['message'] as String?;
    if (event['type'] == 'snapshot') {
      final pending = _snapshots[event['request']];
      if (pending != null && !pending.isCompleted) {
        if (event['composing'] == true) {
          pending.completeError(StateError('请先完成输入法选字'));
        } else {
          pending.complete(event['markdown'] as String);
        }
      }
    }
    notifyListeners();
  }
}
