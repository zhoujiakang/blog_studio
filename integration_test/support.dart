import 'package:blog_studio/controllers/web_markdown_controller.dart';

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:blog_studio/services/template_installer.dart';
import 'package:blog_studio/services/project_service.dart';
import 'package:blog_studio/services/editor_session.dart';

/// Native regression tests use source fixtures, never bundled templates/network.
EditorSession nativeTestSession() {
  const source = String.fromEnvironment('INKJIAN_SOURCE_ROOT');
  final root = source.isEmpty ? Directory.current.path : source;
  return EditorSession(
    editor: WebMarkdownController(),
    projects: ProjectService(
      installer: TemplateInstaller(
        readAsset: (path) => File(p.join(root, path)).readAsBytes(),
      ),
    ),
  );
}

// Native tests intentionally inspect the concrete WebView implementation.
extension NativeEditorInspection on EditorSession {
  WebMarkdownController get nativeEditor => editor as WebMarkdownController;
}
