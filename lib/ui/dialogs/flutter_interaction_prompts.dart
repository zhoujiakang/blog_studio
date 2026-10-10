import 'package:flutter/material.dart';
import 'package:blog_studio/controllers/interaction_prompts.dart';
import 'package:blog_studio/models/blog_template.dart';
import 'package:blog_studio/models/runtime_environment.dart';
import 'package:blog_studio/models/dependency_report.dart';
import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/services/preview_manager.dart';
import 'package:blog_studio/ui/dialogs/preview_preparation_dialog.dart';
import 'package:blog_studio/ui/dialogs/template_picker_dialog.dart';
import 'package:blog_studio/ui/dialogs/new_article_dialog.dart';

class FlutterInteractionPrompts implements InteractionPrompts {
  FlutterInteractionPrompts(this.context, this.isMounted, this.preview);
  final BuildContext Function() context;
  final bool Function() isMounted;
  final PreviewManager preview;
  @override
  void message(String text) {
    if (isMounted()) {
      ScaffoldMessenger.of(context())
          .showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Future<bool> confirm(String title, String message, String action) async {
    if (!isMounted()) return false;
    return await showDialog<bool>(
          context: context(),
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Future<String?> newArticleTitle() => showDialog<String>(
    context: context(),
    builder: (_) => const NewArticleDialog(),
  );
  @override
  Future<String?> chooseInitialTemplate(
    String root,
    List<BlogTemplate> templates,
  ) => showDialog<String>(
    context: context(),
    builder: (_) => TemplatePickerDialog(root: root, templates: templates),
  );
  @override
  Future<String?> chooseStyle(List<BlogTemplate> styles) => showDialog<String>(
    context: context(),
    builder: (context) => SimpleDialog(
      title: const Text('切换博客模板'),
      children: [
        for (final style in styles)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, style.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(style.name),
            ),
          ),
      ],
    ),
  );
  @override
  Future<Uri?> preparePreview(
    ProjectSession project,
    RuntimeEnvironment runtime,
    DependencyReport? report,
  ) => showDialog<Uri>(
    context: context(),
    barrierDismissible: false,
    builder: (_) => PreviewPreparationDialog(
      preview: preview,
      start: () => preview.prepareAndStart(project, runtime, report),
    ),
  );
}
