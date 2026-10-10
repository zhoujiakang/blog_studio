import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:blog_studio/platform/contracts/desktop_platform.dart';
import 'package:blog_studio/app/app_dependencies.dart';
import 'package:blog_studio/controllers/web_markdown_controller.dart';

class WebMarkdownEditor extends StatefulWidget {
  const WebMarkdownEditor({
    super.key,
    required this.controller,
    this.host,
    this.createHost,
  });
  final EditorHost? host;
  final EditorHost Function()? createHost;
  final WebMarkdownController controller;

  @override
  State<WebMarkdownEditor> createState() => _WebMarkdownEditorState();
}

class _WebMarkdownEditorState extends State<WebMarkdownEditor> {
  late final EditorHost web;
  @override
  void initState() {
    super.initState();
    web =
        widget.host ??
        (widget.createHost ?? AppDependencies.current.createEditorHost)();
    widget.controller.attachHost(web);
    unawaited(_loadBundledEditor());
  }

  Future<void> _loadBundledEditor() async {
    try {
      final resources = await Future.wait([
        rootBundle.loadString('assets/editor/editor.js'),
        rootBundle.loadString('assets/editor/index.css'),
      ]);
      if (!mounted) return;
      // WKWebView gives file URLs opaque origins. Inline the trusted bundled
      // resources with a nonce instead of relaxing cross-origin file access.
      final script = resources[0].replaceAll('</script', r'<\/script');
      await web.load(
        '''<!doctype html><html lang="zh-CN"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-studio-editor'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; connect-src 'none'">
<style>${resources[1]}</style></head><body><main id="editor"></main>
<script nonce="studio-editor">
window.addEventListener('error', event => StudioBridge.postMessage(JSON.stringify({protocol:1,type:'error',session:${jsonEncode(widget.controller.protocol.session)},message:event.message})));
</script>
<script nonce="studio-editor">$script</script></body></html>''',
        onMessage: (message) {
          if (mounted && widget.controller.isAttachedTo(web)) {
            widget.controller.receive(message);
          }
        },
        onError: (message) {
          if (mounted) widget.controller.reportError(message);
        },
        onPasteImage: () => widget.controller.onPasteImage?.call(),
      );
    } catch (error) {
      if (mounted) widget.controller.reportError('编辑器资源加载失败：$error');
    }
  }

  @override
  void dispose() {
    web.dispose();
    widget.controller.detachHost(web);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => web.buildView();
}
