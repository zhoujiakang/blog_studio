import 'package:blog_studio/services/taxonomy_catalog.dart';
import 'package:flutter/material.dart';

import 'package:blog_studio/storage/article_repository.dart';

import 'package:blog_studio/ui/components/property_bindings.dart';
import 'package:blog_studio/ui/components/taxonomy_chip.dart';

import 'package:blog_studio/ui/theme/property_style.dart';

class TaxonomyPropertiesTab extends StatefulWidget {
  const TaxonomyPropertiesTab({
    super.key,
    required this.data,
    required this.taxonomyKey,
    required this.label,
  });
  final PropertyBindings data;
  final String taxonomyKey;
  final String label;
  @override
  State<TaxonomyPropertiesTab> createState() => _TaxonomyPropertiesTabState();
}

class _TaxonomyPropertiesTabState extends State<TaxonomyPropertiesTab> {
  bool _pinSaving = false;
  final _selected = <String, List<String>>{};
  @override
  void initState() {
    super.initState();
    _sync();
  }

  void _sync() {
    for (final key in ['tags', 'categories']) {
      _selected[key] = ArticleRepository.values(widget.data.values[key])
          .toSet()
          .toList();
    }
  }

  @override
  void didUpdateWidget(covariant TaxonomyPropertiesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: propertyTextStyle.copyWith(color: const Color(0xff999999)),
    filled: true,
    fillColor: const Color(0xfff7f7f7),
    isDense: true,
    contentPadding: const EdgeInsets.all(12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
  );

  void _choose(String key, String value, {bool remove = false}) {
    final next = [..._selected[key]!];
    if (remove) {
      next.remove(value);
    } else if (!next.contains(value)) {
      next.add(value);
    }
    setState(() => _selected[key] = next);
    widget.data.onChanged({key: next});
  }

  Widget _chip(String text, VoidCallback action, {bool remove = false}) =>
      TaxonomyChip(
        text: text,
        action: action,
        selected: remove,
        style: propertyTextStyle.copyWith(fontSize: 11),
      );
  Future<void> _custom(String key) async {
    widget.data.onFocus?.call();
    final controller = TextEditingController();
    final label = key == 'tags' ? '标签' : '分类';
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '新增自定义$label',
          style: propertyTextStyle.copyWith(fontSize: 16),
        ),
        content: SizedBox(
          width: 320,
          child: TextField(
            controller: controller,
            autofocus: true,
            onTap: widget.data.onFocus,
            maxLength: 80,
            style: propertyTextStyle,
            decoration: _decoration('$label名称'),
            onSubmitted: (s) {
              if (s.trim().isNotEmpty) Navigator.pop(context, s.trim());
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    // The dialog's exit animation may still reference its controller.
    if (mounted && value != null) _choose(key, value);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }

  Future<void> _search(String key) async {
    widget.data.onFocus?.call();
    final label = key == 'tags' ? '标签' : '分类';
    final catalog = TaxonomyCatalog(widget.data.articles, key);
    final all = {
      ...catalog.counts.keys,
      ...widget.data.pins[key] ?? [],
      ..._selected[key]!,
    }.toList();
    final pinned = [...widget.data.pins[key] ?? <String>[]];
    final selected = [..._selected[key]!];
    String query = '';
    String? pinError;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final matches =
              all
                  .where((s) => s.toLowerCase().contains(query.toLowerCase()))
                  .toList()
                ..sort((a, b) {
                  final priority = (pinned.contains(b) ? 1 : 0).compareTo(
                    pinned.contains(a) ? 1 : 0,
                  );
                  if (priority != 0) return priority;
                  final count = (catalog.counts[b] ?? 0).compareTo(
                    catalog.counts[a] ?? 0,
                  );
                  return count == 0 ? a.compareTo(b) : count;
                });
          return AlertDialog(
            title: Text(
              '搜索$label',
              style: propertyTextStyle.copyWith(fontSize: 16),
            ),
            content: SizedBox(
              width: 360,
              height: 390,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    onTap: widget.data.onFocus,
                    style: propertyTextStyle,
                    decoration: _decoration('搜索名称'),
                    onChanged: (s) => update(() => query = s),
                  ),
                  const SizedBox(height: 12),
                  if (pinError != null)
                    Text(
                      pinError!,
                      style: propertyTextStyle.copyWith(color: Colors.red),
                    ),
                  Expanded(
                    child: matches.isEmpty
                        ? Center(
                            child: Text(
                              '没有匹配的$label',
                              style: propertyTextStyle,
                            ),
                          )
                        : ListView.builder(
                            itemCount: matches.length,
                            itemBuilder: (context, index) {
                              final value = matches[index];
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(value, style: propertyTextStyle),
                                subtitle: Text(
                                  '${catalog.counts[value] ?? 0} 篇文章',
                                  style: propertyTextStyle.copyWith(
                                    fontSize: 11,
                                    color: const Color(0xff888888),
                                  ),
                                ),
                                leading: Icon(
                                  selected.contains(value)
                                      ? Icons.check_circle_outline
                                      : Icons.add_circle_outline,
                                  size: 18,
                                ),
                                onTap: () {
                                  final remove = selected.contains(value);
                                  _choose(key, value, remove: remove);
                                  update(() {
                                    if (remove) {
                                      selected.remove(value);
                                    } else {
                                      selected.add(value);
                                    }
                                  });
                                },
                                trailing: IconButton(
                                  tooltip: pinned.contains(value)
                                      ? '取消置顶 $value'
                                      : '置顶 $value',
                                  icon: Icon(
                                    pinned.contains(value)
                                        ? Icons.push_pin
                                        : Icons.push_pin_outlined,
                                    size: 17,
                                  ),
                                  onPressed: _pinSaving
                                      ? null
                                      : () async {
                                          update(() {
                                            _pinSaving = true;
                                            pinError = null;
                                          });
                                          try {
                                            await widget.data.onPin(key, value);
                                            if (context.mounted) {
                                              update(() {
                                                if (!pinned.remove(value)) {
                                                  pinned.add(value);
                                                }
                                              });
                                            }
                                          } catch (e) {
                                            if (context.mounted) {
                                              update(
                                                () => pinError = '置顶保存失败：$e',
                                              );
                                            }
                                          } finally {
                                            _pinSaving = false;
                                            if (context.mounted) update(() {});
                                            if (mounted) setState(() {});
                                          }
                                        },
                                ),
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
                child: const Text('完成'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _taxonomy(String key, String label) {
    final catalog = TaxonomyCatalog(widget.data.articles, key);
    final suggestions = TaxonomySuggestions(
      catalog,
      widget.data.pins[key] ?? [],
      _selected[key]!,
    );
    final pinned = suggestions.pinned,
        recent = suggestions.recent,
        popular = suggestions.popular;
    Widget group(String title, List<String> values) => values.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: propertyTextStyle.copyWith(
                    fontSize: 11,
                    color: const Color(0xff999999),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: values
                      .map((s) => _chip(s, () => _choose(key, s)))
                      .toList(),
                ),
              ],
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: propertyTextStyle.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              '已添加',
              style: propertyTextStyle.copyWith(
                fontSize: 11,
                color: const Color(0xff888888),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${_selected[key]!.length}',
              style: propertyTextStyle.copyWith(
                fontSize: 11,
                color: const Color(0xffaaaaaa),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_selected[key]!.isEmpty)
          Text(
            '还没有添加$label',
            style: propertyTextStyle.copyWith(
              fontSize: 12,
              color: const Color(0xff999999),
            ),
          ),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: _selected[key]!
              .map(
                (s) =>
                    _chip(s, () => _choose(key, s, remove: true), remove: true),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => _custom(key),
              icon: const Icon(Icons.add, size: 14),
              label: Text(
                '新增自定义',
                style: propertyTextStyle.copyWith(fontSize: 11),
              ),
            ),
            TextButton.icon(
              onPressed: () => _search(key),
              icon: const Icon(Icons.search, size: 14),
              label: Text(
                '搜索与置顶',
                style: propertyTextStyle.copyWith(fontSize: 11),
              ),
            ),
          ],
        ),
        if (pinned.isNotEmpty || recent.isNotEmpty || popular.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xffeeeeee)),
          const SizedBox(height: 14),
          Text(
            '可添加',
            style: propertyTextStyle.copyWith(
              fontSize: 11,
              color: const Color(0xff888888),
            ),
          ),
        ],
        group('置顶', pinned),
        group('近期使用', recent),
        group('使用最多', popular),
      ],
    );
  }

  @override
  Widget build(BuildContext context) =>
      _taxonomy(widget.taxonomyKey, widget.label);
}
