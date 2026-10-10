import 'package:flutter/material.dart';

import 'package:blog_studio/models/article.dart';
import 'package:blog_studio/storage/file_store.dart';

import 'package:blog_studio/ui/components/property_bindings.dart';
import 'package:blog_studio/ui/components/basic_properties_tab.dart';
import 'package:blog_studio/ui/components/taxonomy_properties_tab.dart';
import 'package:blog_studio/ui/components/cover_properties_tab.dart';

import 'package:blog_studio/ui/theme/property_style.dart';

class ArticleProperties extends StatefulWidget {
  const ArticleProperties({
    super.key,
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
  @override
  State<ArticleProperties> createState() => _ArticlePropertiesState();
}

class _ArticlePropertiesState extends State<ArticleProperties> {
  int _page = 0;
  PropertyBindings get _bindings => PropertyBindings(
    values: widget.values,
    onChanged: widget.onChanged,
    articles: widget.articles,
    pins: widget.pins,
    onPin: widget.onPin,
    onPickCover: widget.onPickCover,
    store: widget.store,
    importing: widget.importing,
    onFocus: widget.onFocus,
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        child: Text(
          '文章属性',
          style: propertyTextStyle.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xfff3f3f3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Row(
              children: [
                for (final (index, label) in ['基本', '标签', '分类', '封面'].indexed)
                  Expanded(
                    child: Semantics(
                      selected: _page == index,
                      child: TextButton(
                        onPressed: () {
                          FocusScope.of(context).unfocus();
                          setState(() => _page = index);
                        },
                        style: TextButton.styleFrom(
                          backgroundColor: _page == index
                              ? Colors.white
                              : Colors.transparent,
                          foregroundColor: _page == index
                              ? const Color(0xff303030)
                              : const Color(0xff888888),
                          textStyle: propertyTextStyle.copyWith(
                            fontSize: 12,
                            fontWeight: _page == index
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: Text(label),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      const Divider(height: 1, thickness: 1, color: Color(0xffeeeeee)),
      Expanded(
        child: ListView(
          key: ValueKey(_page),
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
          children: [
            switch (_page) {
              0 => BasicPropertiesTab(data: _bindings),
              1 => TaxonomyPropertiesTab(
                data: _bindings,
                taxonomyKey: 'tags',
                label: '标签',
              ),
              2 => TaxonomyPropertiesTab(
                data: _bindings,
                taxonomyKey: 'categories',
                label: '分类',
              ),
              _ => CoverPropertiesTab(data: _bindings),
            },
          ],
        ),
      ),
    ],
  );
}
