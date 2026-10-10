import 'package:flutter/material.dart';

import 'package:blog_studio/models/article.dart';
import 'package:blog_studio/storage/file_store.dart';

class PropertyBindings {
  const PropertyBindings({
    required this.values,
    required this.onChanged,
    required this.articles,
    required this.pins,
    required this.onPin,
    required this.onPickCover,
    required this.store,
    this.importing = false,
    this.onFocus,
  });
  final Map<String, dynamic> values;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final List<ArticleSummary> articles;
  final Map<String, List<String>> pins;
  final Future<void> Function(String, String) onPin;
  final Future<void> Function() onPickCover;
  final FileStore store;
  final bool importing;
  final VoidCallback? onFocus;
}
