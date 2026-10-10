import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/models/runtime_environment.dart';
import 'package:blog_studio/models/dependency_report.dart';
import 'package:blog_studio/services/preview_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('packaged preview helpers start refresh and stop system Node server', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('本地预览验证'))),
    );
    final fixture =
        jsonDecode(await File('build/test-blog.json').readAsString()) as Map;
    final project = ProjectSession(root: fixture['root'] as String);
    final manager = PreviewManager();
    final client = HttpClient();
    try {
      final runtime = await manager.runtimeDetector.detect(project);
      expect(runtime.status, RuntimeStatus.ready);
      final report = await manager.inspect(project, runtime);
      expect(report.status, DependencyStatus.ready, reason: report.reason);
      final url = await manager.start(project, runtime);
      expect(url.host, '127.0.0.1');
      final response = await (await client.getUrl(url.resolve('src/App.vue')))
          .close();
      expect(response.statusCode, 200);
      await response.drain<void>();
      // HTTP 200 alone misses invalid browser imports and CSP failures.
      final web = WebViewController();
      await web.setJavaScriptMode(JavaScriptMode.unrestricted);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WebViewWidget(controller: web)),
        ),
      );
      await web.loadRequest(url);
      String text = '';
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        text =
            '${await web.runJavaScriptReturningResult("document.querySelector('#app')?.innerText || ''")}';
        if (text.contains('最近更新')) break;
      }
      expect(
        text,
        contains('最近更新'),
        reason: 'Vue preview must mount in a real browser',
      );
      expect(text, contains('拾笺'));
      expect(
        await web.runJavaScriptReturningResult(
          "document.querySelector('.post-card') !== null",
        ),
        true,
      );
      await web.runJavaScript(
        "document.querySelector('.post-card h2 a').click()",
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        await web.runJavaScriptReturningResult(
          "(document.querySelector('.prose')?.textContent || '').trim().length > 0",
        ),
        true,
        reason: 'Article Markdown must render through marked and DOMPurify',
      );
      await web.runJavaScript("location.hash = '#/tags'");
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        '${await web.runJavaScriptReturningResult("document.querySelector('#app').innerText")}',
        contains('标签'),
      );
      await manager.refresh();
      await web.reload();
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        text =
            '${await web.runJavaScriptReturningResult("document.querySelector('#app')?.innerText || ''")}';
        if (text.contains('标签')) break;
      }
      expect(
        text,
        contains('标签'),
        reason:
            'Refreshing must retain the active route and render the Vue app',
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      await manager.stop();
      expect(manager.url, isNull);
      await expectLater(client.getUrl(url), throwsA(isA<SocketException>()));
    } finally {
      client.close(force: true);
      await manager.shutdown();
      manager.dispose();
    }
  });
}
