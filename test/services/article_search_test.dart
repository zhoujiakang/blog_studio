import 'package:blog_studio/controllers/web_markdown_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/models/article.dart';
import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/services/article_search.dart';
import 'package:blog_studio/services/editor_session.dart';
import 'package:blog_studio/ui/pages/studio_home.dart';

const articles = [
  ArticleSummary(
    relativePath: 'resource/posts/a.md',
    title: 'Alpha',
    date: '2026-10-08',
    draft: false,
    searchText: '安静的正文',
    tags: ['Vue', 'Vue'],
    categories: ['技术/Vue', '技术'],
  ),
  ArticleSummary(
    relativePath: 'resource/posts/b.md',
    title: 'Beta',
    date: '2026-10-07',
    draft: false,
    searchText: '另一段正文',
    tags: ['Flutter'],
    categories: ['技术/Flutter'],
  ),
  ArticleSummary(
    relativePath: 'resource/drafts/c.md',
    title: 'Unsorted',
    date: '2026-10-06',
    draft: true,
    searchText: '未分类正文',
  ),
];

void main() {
  test('search combines metadata, words, exact tags and category subtrees', () {
    expect(matchesArticle(articles[0], query: 'vue 安静'), true);
    expect(matchesArticle(articles[0], query: 'flutter'), false);
    expect(matchesArticle(articles[0], tag: 'Vu'), false);
    expect(matchesArticle(articles[0], category: '技术'), true);
    expect(matchesArticle(articles[0], category: '技'), false);
    expect(matchesArticle(articles[0], category: '技术/Flutter'), false);
    expect(matchesArticle(articles[2], category: ''), true);
    expect(matchesArticle(articles[0], category: ''), false);
    expect(matchesArticle(articles[1], query: 'Beta', tag: 'Vue'), false);
  });
  test('tree counts unique articles in parents and keeps independent categories separate', () {
    final facets = ArticleFacets(articles);
    expect(facets.tags['Vue'], 1);
    expect(facets.root.children['技术']!.articles.length, 2);
    expect(facets.root.children['技术']!.children['Vue']!.articles.length, 1);
    expect(facets.uncategorized, 1);
    expect(categoryPath(' 技术 / Vue '), '技术/Vue');
    final flat = ArticleFacets([
      const ArticleSummary(
        relativePath: 'x',
        title: 'x',
        date: '',
        draft: false,
        searchText: '',
        categories: ['日记', '生活'],
      ),
    ]);
    expect(flat.root.children.keys, containsAll(['日记', '生活']));
    expect(flat.root.children['日记']!.children, isEmpty);
  });
  testWidgets(
    'minimum window supports metadata search, tree selection and tag intersections',
    (tester) async {
      tester.view.physicalSize = const Size(900, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('window_manager'),
            (_) async => null,
          );
      final session = EditorSession(editor: WebMarkdownController())
        ..project = const ProjectSession(root: '/tmp/local-blog')
        ..index = const ArticleIndex(articles);
      await tester.pumpWidget(MaterialApp(home: StudioHome(session: session)));
      await tester.enterText(find.byType(TextField), 'Vue');
      await tester.pump();
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pump();
      await tester.tap(find.byTooltip('展开分类导航'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('展开 技术'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vue'));
      await tester.pump();
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);
      expect(find.text('分类：技术/Vue'), findsOneWidget);
      expect(find.byTooltip('查看当前筛选'), findsNothing);
      await tester.tap(find.byTooltip('按标签筛选'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '搜索标签'), 'Flutter');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Flutter'));
      await tester.pumpAndSettle();
      expect(find.text('没有找到匹配的内容'), findsOneWidget);
      await tester.tap(find.byTooltip('清除分类筛选'));
      await tester.pumpAndSettle();
      expect(find.text('Beta'), findsOneWidget);
      await tester.tap(find.byTooltip('清除标签筛选'));
      await tester.pumpAndSettle();
      expect(find.text('Beta'), findsOneWidget);
      await tester.tap(find.text('未分类'));
      await tester.pump();
      expect(find.text('Unsorted'), findsOneWidget);
      expect(find.text('Alpha'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
