import 'package:blog_studio/controllers/web_markdown_controller.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/services/editor_session.dart';
import 'package:blog_studio/storage/article_repository.dart';
import 'package:blog_studio/storage/blog_configuration.dart';
import 'package:blog_studio/ui/pages/general_configuration_page.dart';

void main() {
  testWidgets(
    'general configuration offers avatar picker, preview and removal at minimum width',
    (tester) async {
      tester.view.physicalSize = const Size(680, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = Directory.systemTemp.createTempSync('inkjian-avatar-ui-');
      final session = EditorSession(editor: WebMarkdownController());
      var selections = 0;
      try {
        session.project = ProjectSession(root: root.path);
        session.repository = ArticleRepository(root.path);
        session.general.load(BlogConfiguration({'site': {}}, 'hash'));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AnimatedBuilder(
                animation: session,
                builder: (context, _) => GeneralConfigurationPage(
                  session: session,
                  onPickAvatar: () async {
                    selections++;
                  },
                ),
              ),
            ),
          ),
        );
        expect(find.text('头像'), findsOneWidget);
        await tester.tap(find.text('选择头像'));
        expect(selections, 1);
        expect(tester.takeException(), isNull);
        session.updateGeneralConfiguration('avatar', '/img/missing.png');
        await tester.pump();
        expect(find.text('更换头像'), findsOneWidget);
        await tester.tap(find.text('移除头像'));
        await tester.pump();
        expect(session.generalConfiguration!.value('avatar'), '');
        expect(find.text('选择头像'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        session.dispose();
        root.deleteSync(recursive: true);
      }
    },
  );
}
