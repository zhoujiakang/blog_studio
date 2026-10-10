import 'package:flutter/material.dart';

import 'package:blog_studio/app/app_dependencies.dart';
import 'package:blog_studio/app.dart';
export 'package:blog_studio/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDependencies.current.window.initialize();
  runApp(const StudioApp());
}
