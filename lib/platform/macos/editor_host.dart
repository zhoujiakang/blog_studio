import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:blog_studio/platform/contracts/desktop_platform.dart';

class MacEditorHost implements EditorHost {
  static const _focusChannel = MethodChannel('blog_studio/editor_focus');
  final _web = WebViewController();
  @override
  Widget buildView() => WebViewWidget(controller: _web);
  @override
  Future<void> load(
    String html, {
    required void Function(String) onMessage,
    required void Function(String) onError,
    required VoidCallback onPasteImage,
  }) async {
    _focusChannel.setMethodCallHandler((call) async {
      if (call.method == 'pasteImage') onPasteImage();
    });
    await _web.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _web.addJavaScriptChannel(
      'StudioBridge',
      onMessageReceived: (m) => onMessage(m.message),
    );
    await _web.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (r) => r.url == 'about:blank'
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
        onWebResourceError: (e) => onError('编辑器加载失败：${e.description}'),
      ),
    );
    await _web.loadHtmlString(html);
  }

  @override
  Future<void> execute(String script) => _web.runJavaScript(script);
  @override
  Future<Object> evaluate(String script) =>
      _web.runJavaScriptReturningResult(script);
  @override
  Future<bool> focus() async =>
      await _focusChannel.invokeMethod<bool>('focus') ?? false;
  @override
  Future<void> releaseKeyboard() => _focusChannel.invokeMethod('blur');
  @override
  Future<Map<dynamic, dynamic>?> focusState() =>
      _focusChannel.invokeMapMethod('state');
  @override
  void dispose() {
    _focusChannel.setMethodCallHandler(null);
  }
}
