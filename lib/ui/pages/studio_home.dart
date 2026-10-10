import 'package:blog_studio/controllers/web_markdown_controller.dart';
import 'package:blog_studio/controllers/publish_controller.dart';
import 'package:blog_studio/services/publishing/blog_builder.dart';
import 'package:blog_studio/services/publishing/github_auth.dart';
import 'package:blog_studio/ui/pages/publishing_page.dart';
import 'package:blog_studio/services/runtime_detector.dart';
import 'package:blog_studio/services/managed_runtime.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:blog_studio/ui/components/studio_sidebar.dart';

import 'package:blog_studio/ui/pages/general_configuration_page.dart';

import 'package:blog_studio/app/app_dependencies.dart';
import 'package:blog_studio/controllers/studio_controller.dart';

import 'package:blog_studio/ui/dialogs/flutter_interaction_prompts.dart';

import 'package:blog_studio/services/editor_session.dart';
import 'package:blog_studio/services/preview_manager.dart';
import 'package:blog_studio/ui/pages/library_page.dart';
import 'package:blog_studio/ui/pages/writing_page.dart';
import 'package:blog_studio/ui/pages/trash_page.dart';
import 'package:blog_studio/ui/pages/welcome_page.dart';
import 'package:blog_studio/ui/pages/template_configuration_page.dart';

class StudioHome extends StatefulWidget {
  const StudioHome({super.key, this.session, this.dependencies});
  final EditorSession? session;
  final AppDependencies? dependencies;
  @override
  State<StudioHome> createState() => _StudioHomeState();
}

class _StudioHomeState extends State<StudioHome> {
  late final StudioController controller;
  late final AppDependencies dependencies;
  EditorSession get session => controller.session;
  PreviewManager get preview => controller.preview;
  String get filter => controller.filter;
  bool get preparingPreview => controller.preparingPreview;
  void _changed() {
    if (mounted) setState(() {});
  }

  void _onClose() => unawaited(controller.close());
  @override
  void initState() {
    super.initState();
    dependencies = widget.dependencies ?? AppDependencies.current;
    final runtimeDetector = RuntimeDetector(
      platform: dependencies.runtime,
      processes: dependencies.processes,
    );
    final preview = PreviewManager(
      runtimeDetector: runtimeDetector,
      managedRuntime: ManagedRuntime(
        platform: dependencies.runtime,
        processes: dependencies.processes,
      ),
    );
    controller = StudioController(
      session: widget.session ?? EditorSession(editor: WebMarkdownController()),
      preview: preview,
      prompts: FlutterInteractionPrompts(() => context, () => mounted, preview),
      dependencies: dependencies,
      publisher: PublishController(
        auth: GitHubAuth(store: dependencies.credentials),
        builder: BlogBuilder(preview),
        browser: dependencies.browser,
        onConfigurationChanged: () => session.reloadGeneralConfiguration(),
      ),
    );
    controller.addListener(_changed);
    dependencies.window.watchClose(_onClose);
  }

  @override
  void dispose() {
    dependencies.window.unwatchClose(_onClose);
    controller.removeListener(_changed);
    controller.publisher?.dispose();
    controller.dispose();
    preview.dispose();
    if (widget.session == null) session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            StudioSidebar(controller: controller),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Material(
                  color: Colors.white,
                  child: session.project == null
                      ? WelcomePage(controller: controller)
                      : session.article != null
                      ? WritingPage(controller: controller)
                      : filter == 'publish'
                      ? PublishingPage(controller: controller.publisher!)
                      : filter == 'general'
                      ? GeneralConfigurationPage(
                          session: session,
                          onPickAvatar: controller.pickAvatar,
                        )
                      : filter == 'configuration'
                      ? TemplateConfigurationPage(
                          session: session,
                          onSwitch: controller.switchStyle,
                          onPickImage: controller.pickConfigurationImage,
                        )
                      : filter == 'trash'
                      ? TrashPage(controller: controller)
                      : LibraryPage(controller: controller),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
