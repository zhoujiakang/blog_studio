import 'package:flutter/material.dart';

import 'package:blog_studio/models/article.dart';
import 'package:blog_studio/services/article_search.dart';

Future<String?> pickArticleTag(
  BuildContext context,
  List<ArticleSummary> articles,
  String? selected,
) {
  final facets = ArticleFacets(articles);
  final tags = facets.tags.keys.toList()
    ..sort(
      (a, b) => facets.tags[b]!.compareTo(facets.tags[a]!) != 0
          ? facets.tags[b]!.compareTo(facets.tags[a]!)
          : a.compareTo(b),
    );
  var query = '';
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) {
        final visible = tags
            .where((s) => s.toLowerCase().contains(query.toLowerCase()))
            .toList();
        return AlertDialog(
          title: const Text('按标签筛选', style: TextStyle(fontSize: 17)),
          content: SizedBox(
            width: 360,
            height: 380,
            child: Column(
              children: [
                TextField(
                  autofocus: true,
                  onChanged: (value) => update(() => query = value),
                  decoration: const InputDecoration(
                    hintText: '搜索标签',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('全部标签'),
                  onTap: () => Navigator.pop(context, ''),
                  trailing: selected == null
                      ? const Icon(Icons.check, size: 16)
                      : null,
                ),
                Expanded(
                  child: visible.isEmpty
                      ? const Center(child: Text('没有匹配的标签'))
                      : ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (_, i) {
                            final tag = visible[i];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                tag,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${facets.tags[tag]} 篇文章',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: selected == tag
                                  ? const Icon(Icons.check, size: 16)
                                  : null,
                              onTap: () => Navigator.pop(context, tag),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        );
      },
    ),
  );
}

class ArticleCategories extends StatefulWidget {
  const ArticleCategories({
    super.key,
    required this.articles,
    required this.selected,
    required this.onSelected,
  });
  final List<ArticleSummary> articles;
  final String? selected;
  final ValueChanged<String?> onSelected;
  @override
  State<ArticleCategories> createState() => _ArticleCategoriesState();
}

class _ArticleCategoriesState extends State<ArticleCategories> {
  String query = '';
  final expanded = <String>{};

  @override
  Widget build(BuildContext context) {
    final facets = ArticleFacets(widget.articles);
    final rows = <(CategoryNode, int)>[];
    void visit(CategoryNode node, int depth) {
      if (query.isNotEmpty && !node.containsQuery(query.toLowerCase())) return;
      rows.add((node, depth));
      if (query.isNotEmpty || expanded.contains(node.path)) {
        for (final child in node.sorted) {
          visit(child, depth + 1);
        }
      }
    }

    for (final node in facets.root.sorted) {
      visit(node, 0);
    }
    Widget option(String label, String? value, int count) => ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      selected: widget.selected == value,
      selectedTileColor: const Color(0xffeeeeee),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      title: Text(label, style: const TextStyle(fontSize: 12)),
      trailing: Text(
        '$count',
        style: const TextStyle(fontSize: 11, color: Color(0xff999999)),
      ),
      onTap: () => widget.onSelected(value),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '分类导航',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        TextField(
          onChanged: (value) => setState(() => query = value.trim()),
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            hintText: '搜索分类',
            prefixIcon: Icon(Icons.search, size: 16),
          ),
        ),
        const SizedBox(height: 8),
        option('全部分类', null, widget.articles.length),
        option('未分类', '', facets.uncategorized),
        const Divider(color: Color(0xffeeeeee)),
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: Text(
                    '没有匹配的分类',
                    style: TextStyle(fontSize: 12, color: Color(0xff999999)),
                  ),
                )
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final (node, depth) = rows[i];
                    final isExpanded =
                        query.isNotEmpty || expanded.contains(node.path);
                    return Padding(
                      padding: EdgeInsets.only(
                        left: (depth > 4 ? 4 : depth) * 10.0,
                      ),
                      child: Material(
                        color: widget.selected == node.path
                            ? const Color(0xffeeeeee)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 26,
                              child: node.children.isEmpty
                                  ? const Icon(
                                      Icons.folder_outlined,
                                      size: 14,
                                      color: Color(0xff999999),
                                    )
                                  : IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 26,
                                        minHeight: 36,
                                      ),
                                      tooltip:
                                          '${isExpanded ? '收起' : '展开'} ${node.name}',
                                      onPressed: () => setState(() {
                                        if (!expanded.remove(node.path)) {
                                          expanded.add(node.path);
                                        }
                                      }),
                                      icon: Icon(
                                        isExpanded
                                            ? Icons.keyboard_arrow_down
                                            : Icons.keyboard_arrow_right,
                                        size: 17,
                                      ),
                                    ),
                            ),
                            Expanded(
                              child: Tooltip(
                                message: node.path,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(6),
                                  onTap: () => widget.onSelected(node.path),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 11,
                                      horizontal: 4,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            node.name,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${node.articles.length}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xff999999),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
