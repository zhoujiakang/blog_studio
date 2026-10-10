import 'package:blog_studio/models/blog_template.dart';
import 'package:blog_studio/models/runtime_environment.dart';
import 'package:blog_studio/models/dependency_report.dart';
import 'package:blog_studio/models/project.dart';

abstract interface class InteractionPrompts {
  void message(String text);
  Future<bool> confirm(String title, String message, String action);
  Future<String?> newArticleTitle();
  Future<String?> chooseInitialTemplate(
    String root,
    List<BlogTemplate> templates,
  );
  Future<String?> chooseStyle(List<BlogTemplate> styles);
  Future<Uri?> preparePreview(
    ProjectSession project,
    RuntimeEnvironment runtime,
    DependencyReport? report,
  );
}
