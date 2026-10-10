import 'package:blog_studio/controllers/web_markdown_controller.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/services/editor_session.dart';
import 'package:blog_studio/services/project_service.dart';
import 'package:blog_studio/services/template_installer.dart';
import 'package:blog_studio/ui/pages/template_configuration_page.dart';

void main() {
  testWidgets('dynamic text, image, color fields save and restore defaults', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1120, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('studio-config-widget-'),
    ))!;
    final session = EditorSession(editor: WebMarkdownController());
    String? selectedImageKey;
    try {
      final installer = TemplateInstaller(
        readAsset: (path) => File(path).readAsBytes(),
      );
      await tester.runAsync(
        () => ProjectService(installer: installer).initialize(root.path),
      );
      expect(await tester.runAsync(() => session.openProject(root.path)), true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: session,
              builder: (context, _) => TemplateConfigurationPage(
                session: session,
                onSwitch: () {},
                onPickImage: (key) async {
                  selectedImageKey = key;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('背景图片'), findsOneWidget);
      expect(find.text('选择图片'), findsOneWidget);
      await tester.tap(find.text('选择图片'));
      await tester.pump();
      expect(
        selectedImageKey,
        session.configuration!.fields.firstWhere(
          (field) => field['type'] == 'image',
        )['key'],
      );
      expect(find.text('主题颜色'), findsOneWidget);
      expect(find.text('公告'), findsOneWidget);
      await tester.tap(find.text('选择颜色'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNWidgets(3));
      await tester.tap(find.text('使用此颜色'));
      await tester.pumpAndSettle();
      final textField = find.byType(TextField).last;
      await tester.enterText(textField, '实时配置公告');
      await tester.pump();
      expect(session.dirty, true);
      await tester.runAsync(() => session.flush());
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(
          () =>
              File('${root.path}/template/butterfly/template.json')
                  .readAsString(),
        ),
        contains('实时配置公告'),
      );
      await tester.ensureVisible(find.text('恢复默认'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复默认'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复默认').last);
      await tester.pumpAndSettle();
      expect(
        session.configuration!.fields.firstWhere(
          (f) => f['key'] == 'announcement',
        )['value'],
        isNot('实时配置公告'),
      );
      await tester.runAsync(() => session.flush());
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      session.dispose();
      await tester.runAsync(() => root.delete(recursive: true));
    }
  });
}
