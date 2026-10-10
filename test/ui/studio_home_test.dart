import 'package:blog_studio/controllers/web_markdown_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/services/editor_session.dart';
import 'package:blog_studio/models/article.dart';
import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/main.dart';
import 'package:blog_studio/ui/pages/studio_home.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (_) async => null,
        );
  });
  testWidgets(
    'welcome fits minimum desktop size and exposes folder selection',
    (tester) async {
      tester.view.physicalSize = const Size(900, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const StudioApp());
      expect(find.text('选择目录'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('library searches titles and body and displays draft status', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = EditorSession(editor: WebMarkdownController());
    session.project = const ProjectSession(root: '/tmp/local-blog');
    session.index = const ArticleIndex([
      ArticleSummary(
        relativePath: 'resource/posts/a.md',
        title: '第一篇',
        date: '2026-10-08',
        draft: false,
        searchText: '第一篇\n匹配正文',
      ),
      ArticleSummary(
        relativePath: 'resource/drafts/b.md',
        title: '草稿标题',
        date: '2026-10-07',
        draft: true,
        searchText: '草稿标题\n其他正文',
      ),
    ]);
    await tester.pumpWidget(MaterialApp(home: StudioHome(session: session)));
    expect(find.text('浏览本地博客'), findsOneWidget);
    expect(find.text('新建文章'), findsOneWidget);
    expect(find.text('新建小记'), findsOneWidget);
    await tester.tap(find.text('小记'));
    await tester.pumpAndSettle();
    expect(find.text('新建文章'), findsOneWidget);
    expect(find.text('新建小记'), findsOneWidget);
    await tester.tap(find.text('全部文章'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '匹配正文');
    await tester.pump();
    expect(find.text('第一篇'), findsOneWidget);
    expect(find.text('草稿标题'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
