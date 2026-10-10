import 'package:flutter/material.dart';
import 'package:blog_studio/controllers/studio_controller.dart';
import 'package:blog_studio/services/editor_session.dart';

import 'package:blog_studio/ui/components/article_filters.dart';

import 'package:blog_studio/services/article_search.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.controller});
  final StudioController controller;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  bool get preparingPreview => controller.preparingPreview;
  StudioController get controller => widget.controller;
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  EditorSession get session => controller.session;
  String get filter => controller.filter;
  set filter(String value) => controller.filter = value;
  String? get selectedTag => controller.selectedTag;
  set selectedTag(String? value) => controller.selectedTag = value;
  String? get selectedCategory => controller.selectedCategory;
  set selectedCategory(String? value) => controller.selectedCategory = value;
  bool get categoryBrowser => controller.categoryBrowser;
  set categoryBrowser(bool value) => controller.categoryBrowser = value;
  Widget _filterSummary(bool isNotes, int count, String query) {
    Widget condition(
      String label,
      String tooltip,
      VoidCallback remove,
    ) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InputChip(
        label: Tooltip(
          message: label,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xff666666)),
            ),
          ),
        ),
        onDeleted: remove,
        deleteButtonTooltipMessage: tooltip,
        deleteIcon: const Icon(Icons.close, size: 13, color: Color(0xff999999)),
        backgroundColor: const Color(0xfff5f5f5),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
    final conditions = <Widget>[
      if (!isNotes && selectedCategory != null)
        condition(
          '分类：${selectedCategory!.isEmpty ? '未分类' : selectedCategory}',
          '清除分类筛选',
          () => controller.update(() => selectedCategory = null),
        ),
      if (!isNotes && selectedTag != null)
        condition(
          '标签：$selectedTag',
          '清除标签筛选',
          () => controller.update(() => selectedTag = null),
        ),
      if (query.isNotEmpty)
        condition(
          '关键词：$query',
          '清空搜索条件',
          () => controller.update(() => controller.query = ''),
        ),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (conditions.isNotEmpty)
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(mainAxisSize: MainAxisSize.min, children: conditions),
            ),
          ),
        if (conditions.isNotEmpty) const SizedBox(width: 4),
        Text(
          '$count ${isNotes ? '条' : '篇'}',
          style: const TextStyle(fontSize: 11, color: Color(0xff999999)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (search.text != controller.query) {
      search.text = controller.query;
    }
    final result = LibraryResults(
      index: session.index,
      notes: session.notes,
      section: filter,
      search: controller.query,
      tag: selectedTag,
      category: selectedCategory,
    );
    final query = result.query, isNotes = result.isNotes;
    final pool = result.pool, articles = result.articles;
    return Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Text(
                  isNotes
                      ? '小记'
                      : filter == 'drafts'
                      ? '草稿'
                      : '文章',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: _filterSummary(isNotes, articles.length, query),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: constraints.maxWidth < 700 ? 170 : 230,
                  child: TextField(
                    controller: search,
                    style: const TextStyle(fontSize: 12),
                    onChanged: (value) =>
                        controller.update(() => controller.query = value),
                    decoration: InputDecoration(
                      hintText: isNotes ? '搜索小记' : '搜索文章',
                      prefixIcon: const Icon(Icons.search, size: 17),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清空搜索',
                              icon: const Icon(Icons.close, size: 15),
                              onPressed: () => controller.update(
                                () => controller.query = '',
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (!isNotes) ...[
                  IconButton(
                    tooltip: '按标签筛选',
                    constraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 36,
                    ),
                    padding: const EdgeInsets.all(8),
                    onPressed: () async {
                      final value = await pickArticleTag(
                        context,
                        pool,
                        selectedTag,
                      );
                      if (mounted && value != null) {
                        controller.update(
                          () => selectedTag = value.isEmpty ? null : value,
                        );
                      }
                    },
                    icon: const Icon(Icons.sell_outlined, size: 17),
                  ),
                  IconButton(
                    tooltip: categoryBrowser ? '收起分类导航' : '展开分类导航',
                    constraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 36,
                    ),
                    padding: const EdgeInsets.all(8),
                    style: IconButton.styleFrom(
                      backgroundColor: categoryBrowser
                          ? const Color(0xfff0f0f0)
                          : Colors.transparent,
                    ),
                    onPressed: () => controller.update(
                      () => categoryBrowser = !categoryBrowser,
                    ),
                    icon: Icon(
                      categoryBrowser
                          ? Icons.folder_open_outlined
                          : Icons.folder_outlined,
                      size: 17,
                    ),
                  ),
                ],
                IconButton(
                  tooltip: '刷新文章',
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 36,
                  ),
                  padding: const EdgeInsets.all(8),
                  onPressed: () => session.refresh(),
                  icon: const Icon(Icons.refresh, size: 18),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (result.errors.isNotEmpty)
            Text(
              '有 ${result.errors.length} 个文件无法读取：${result.errors.keys.join('、')}',
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (categoryBrowser && !isNotes) ...[
                  SizedBox(
                    width: 180,
                    child: ArticleCategories(
                      articles: pool,
                      selected: selectedCategory,
                      onSelected: (value) =>
                          controller.update(() => selectedCategory = value),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const VerticalDivider(width: 1, color: Color(0xffeeeeee)),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: articles.isEmpty
                      ? Center(
                          child: Text(
                            query.isEmpty &&
                                    (isNotes ||
                                        (selectedTag == null &&
                                            selectedCategory == null))
                                ? (isNotes ? '随手记下今天的小事。' : '还没有文章，写下第一篇吧。')
                                : '没有找到匹配的内容',
                            style: const TextStyle(color: Color(0xff888888)),
                          ),
                        )
                      : ListView.separated(
                          itemCount: articles.length,
                          separatorBuilder: (_, _) =>
                              const Divider(color: Color(0xffeeeeee)),
                          itemBuilder: (context, i) {
                            final a = articles[i];
                            final tile = ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 0,
                              ),
                              leading: const Icon(
                                Icons.description_outlined,
                                color: Color(0xff777777),
                              ),
                              title: Text(
                                a.title,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '${a.date.split(' ').first}  ${a.tags.join(' · ')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    isNotes
                                        ? '小记'
                                        : a.draft
                                        ? '草稿'
                                        : '文章',
                                    style: const TextStyle(
                                      color: Color(0xff888888),
                                      fontSize: 12,
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    tooltip: isNotes ? '管理小记' : '管理文章',
                                    enabled:
                                        !session.busy &&
                                        !preparingPreview &&
                                        !session.importing,
                                    icon: const Icon(
                                      Icons.more_horiz,
                                      size: 18,
                                    ),
                                    onSelected: (value) =>
                                        controller.manageArticle(
                                          value,
                                          a.relativePath,
                                          a.draft,
                                        ),
                                    itemBuilder: (_) => [
                                      if (!isNotes)
                                        PopupMenuItem(
                                          value: 'state',
                                          child: Text(
                                            a.draft ? '转为正式文章' : '转为草稿',
                                          ),
                                        ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text('移入回收区'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              onTap: session.busy
                                  ? null
                                  : () =>
                                        controller.openArticle(a.relativePath),
                            );
                            final day = a.date.split(' ').first;
                            if (!isNotes ||
                                (i > 0 &&
                                    articles[i - 1].date.split(' ').first ==
                                        day)) {
                              return tile;
                            }
                            final today = DateTime.now()
                                .toIso8601String()
                                .substring(0, 10);
                            final yesterday = DateTime.now()
                                .subtract(const Duration(days: 1))
                                .toIso8601String()
                                .substring(0, 10);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 16,
                                    bottom: 4,
                                  ),
                                  child: Text(
                                    day == today
                                        ? '今天 · $day'
                                        : day == yesterday
                                        ? '昨天 · $day'
                                        : day,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xff999999),
                                    ),
                                  ),
                                ),
                                tile,
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
