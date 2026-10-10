import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/controllers/publish_controller.dart';
import 'package:blog_studio/platform/contracts/credential_store.dart';
import 'package:blog_studio/platform/contracts/desktop_platform.dart';
import 'package:blog_studio/services/preview_manager.dart';
import 'package:blog_studio/services/publishing/blog_builder.dart';
import 'package:blog_studio/services/publishing/github_auth.dart';
import 'package:blog_studio/ui/pages/publishing_page.dart';

class Browser implements ExternalBrowser {
  @override
  Future<void> open(Uri url) async {}
}

void main() {
  testWidgets(
    'publishing fits minimum window and explains missing login configuration',
    (tester) async {
      tester.view.physicalSize = const Size(680, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final environment = PreviewManager();
      final controller = PublishController(
        auth: GitHubAuth(
          store: const UnavailableCredentialStore(),
          settings: const GitHubAppSettings(clientId: '', slug: ''),
        ),
        builder: BlogBuilder(environment),
        browser: Browser(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PublishingPage(controller: controller)),
        ),
      );
      expect(find.textContaining('尚未配置 GitHub'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '连接 GitHub'),
      );
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      environment.dispose();
    },
  );
}
