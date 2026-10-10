import 'package:blog_studio/services/taxonomy_catalog.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/models/article.dart';
import 'package:blog_studio/storage/taxonomy_preferences.dart';
import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/storage/path_guard.dart';
import 'package:blog_studio/ui/components/article_properties.dart';

ArticleSummary article(String id, String date, List<String> tags) =>
    ArticleSummary(
      relativePath: id,
      title: id,
      date: date,
      draft: false,
      searchText: '',
      tags: tags,
    );

void main() {
  test('recommendations count articles once and order recent and popular independently', () {
    final catalog = TaxonomyCatalog([
      article('old', '2025-01-01', ['popular', 'popular']),
      article('new', '2026-10-08', ['recent']),
      article('other', '2026-09-01', ['popular']),
    ], 'tags');
    expect(catalog.counts['popular'], 2);
    expect(catalog.popular.first, 'popular');
    expect(catalog.recent.first, 'recent');
  });

  test(
    'pins survive reopen and concurrent toggles without altering articles',
    () async {
      final root = await Directory.systemTemp.createTemp('studio-pins-test-');
      try {
        final store = FileStore(PathGuard(root.path));
        final prefs = TaxonomyPreferences(store);
        await prefs.load();
        await Future.wait([
          prefs.toggle('tags', 'Flutter'),
          prefs.toggle('tags', '写作'),
          prefs.toggle('categories', '笔记'),
        ]);
        final reopened = TaxonomyPreferences(store);
        await reopened.load();
        expect(reopened.pins['tags'], ['Flutter', '写作']);
        expect(reopened.pins['categories'], ['笔记']);
        await reopened.toggle('tags', 'Flutter');
        expect(reopened.pins['tags'], ['写作']);
        expect(await Directory('${root.path}/source').exists(), false);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'date retains time and zone; tabs support remove, custom, search and pins',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('studio-properties-test-'),
      ))!;
      var values = <String, dynamic>{
        'title': '原文标题',
        'date': '2026-10-08T10:23:45+08:00',
        'tags': ['chosen'],
        'categories': [],
      };
      var pins = <String, List<String>>{'tags': [], 'categories': []};
      final articles = List.generate(
        40,
        (i) => article(
          '$i',
          '2026-10-${(i % 8 + 1).toString().padLeft(2, '0')}',
          ['tag$i'],
        ),
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 288,
                  child: StatefulBuilder(
                    builder: (context, update) => ArticleProperties(
                      values: values,
                      articles: articles,
                      pins: pins,
                      store: FileStore(PathGuard(root.path)),
                      onChanged: (v) =>
                          update(() => values = {...values, ...v}),
                      onPickCover: () async {},
                      onPin: (key, value) async => update(
                        () => pins = {
                          ...pins,
                          key: [...pins[key]!, value],
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('2026-10-08'));
        await tester.pumpAndSettle();
        final calendar = tester.widget<CalendarDatePicker>(
          find.byType(CalendarDatePicker),
        );
        calendar.onDateChanged(DateTime(2026, 10, 12));
        await tester.pump();
        await tester.tap(find.text('确定'));
        await tester.pumpAndSettle();
        expect(values['date'], '2026-10-12T10:23:45+08:00');
        await tester.tap(find.widgetWithText(TextButton, '标签'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('移除 chosen'));
        await tester.pumpAndSettle();
        expect(values['tags'], isEmpty);
        expect(find.byType(InputChip).evaluate().length, lessThan(15));
        await tester.tap(find.widgetWithText(TextButton, '新增自定义').first);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '我的新标签');
        await tester.tap(find.text('添加'));
        await tester.pumpAndSettle();
        expect(values['tags'], ['我的新标签']);
        await tester.tap(find.widgetWithText(TextButton, '搜索与置顶').first);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'tag39');
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, 'tag39'));
        await tester.pumpAndSettle();
        expect(values['tags'], contains('tag39'));
        await tester.tap(find.byTooltip('置顶 tag39'));
        await tester.pumpAndSettle();
        expect(pins['tags'], contains('tag39'));
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, '分类'));
        await tester.pumpAndSettle();
        expect(find.text('我的新标签'), findsNothing);
        await tester.tap(find.widgetWithText(TextButton, '标签'));
        await tester.pumpAndSettle();
        expect(find.text('我的新标签'), findsOneWidget);
        expect(values['tags'], contains('tag39'));
        await tester.tap(find.widgetWithText(TextButton, '基本'));
        await tester.pumpAndSettle();
        expect(find.text('原文标题'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, '封面'));
        await tester.pumpAndSettle();
        expect(find.text('选择封面图片'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      } finally {
        await tester.runAsync(() => root.delete(recursive: true));
      }
    },
  );
}
