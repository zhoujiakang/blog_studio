import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:blog_studio/app/brand.dart';

/// Application presentation defaults, independent of the operating system.
const studioWindowOptions = WindowOptions(
  size: Size(1120, 800),
  minimumSize: Size(900, 640),
  title: AppBrand.displayName,
  backgroundColor: Color(0xfff0f0f0),
);
