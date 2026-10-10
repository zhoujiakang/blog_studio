import 'package:blog_studio/app/brand.dart';
import 'package:flutter/material.dart';

import 'package:blog_studio/ui/pages/studio_home.dart';

import 'package:blog_studio/ui/theme/studio_theme.dart';

class StudioApp extends StatelessWidget {
  const StudioApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: AppBrand.displayName,
    debugShowCheckedModeBanner: false,
    theme: studioTheme(),
    home: const StudioHome(),
  );
}
