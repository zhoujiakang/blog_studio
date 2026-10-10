import 'package:blog_studio/app/app_dependencies.dart';

import 'local_blog_flow_test.dart' as local;
import 'editor_reopen_test.dart' as reopen;
import 'milkdown_native_test.dart' as editor;
import 'preview_native_test.dart' as preview;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await AppDependencies.current.window.initialize();
    // Let the native accessibility bridge initialize before the first test
    // records its baseline of SemanticsHandles. A late OS-owned handle is not
    // a leaked handle created by the editor under test.
    final policy = binding.framePolicy;
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    runApp(const MaterialApp(home: SizedBox()));
    await binding.endOfFrame;
    await binding.endOfFrame;
    binding.framePolicy = policy;
  });
  reopen.main();
  local.main();
  editor.main();
  preview.main();
}
