import 'package:flutter/material.dart';

import 'package:blog_studio/models/article.dart';
import 'package:blog_studio/storage/article_repository.dart';

class NotesReference extends StatefulWidget {
  const NotesReference({
    super.key,
    required this.notes,
    required this.repository,
    required this.onInsert,
    required this.onFocus,
    required this.blocked,
  });
  final ArticleIndex notes;
  final ArticleRepository repository;
  final Future<void> Function(String) onInsert;
  final VoidCallback onFocus;
  final bool blocked;
  @override
  State<NotesReference> createState() => _NotesReferenceState();
}

class _NotesReferenceState extends State<NotesReference> {
  String query = '', day = '';
  ArticleSnapshot? selected;
  String? error;
  int request = 0;
  @override
  Widget build(BuildContext context) {
    final days = widget.notes.articles
        .map((a) => a.date.split(' ').first)
        .toSet()
        .toList();
    final filtered = widget.notes.articles
        .where(
          (a) =>
              (day.isEmpty || a.date.startsWith(day)) &&
              a.searchText.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '小记参考',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          TextField(
            onTap: widget.onFocus,
            onChanged: (value) => setState(() => query = value),
            decoration: const InputDecoration(
              hintText: '搜索小记',
              prefixIcon: Icon(Icons.search, size: 18),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButton<String>(
            isExpanded: true,
            value: days.contains(day) ? day : '',
            items: [
              const DropdownMenuItem(value: '', child: Text('全部日期')),
              ...days.map((d) => DropdownMenuItem(value: d, child: Text(d))),
            ],
            onChanged: (value) => setState(() => day = value ?? ''),
          ),
          Expanded(
            child: selected == null
                ? ListView(
                    children: [
                      if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            '没有匹配的小记',
                            style: TextStyle(color: Color(0xff999999)),
                          ),
                        ),
                      ...filtered.map(
                        (note) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            note.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            note.date,
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: () async {
                            widget.onFocus();
                            final current = ++request;
                            try {
                              final snapshot = await widget.repository.read(
                                note.relativePath,
                              );
                              if (mounted && current == request) {
                                setState(() {
                                  selected = snapshot;
                                  error = null;
                                });
                              }
                            } catch (e) {
                              if (mounted) setState(() => error = '$e');
                            }
                          },
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextButton.icon(
                        onPressed: () => setState(() => selected = null),
                        icon: const Icon(Icons.arrow_back, size: 16),
                        label: const Text('返回小记列表'),
                      ),
                      Text(
                        selected!.frontMatter['date']?.toString() ?? '',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xff999999),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: SingleChildScrollView(
                          child: SelectableText(
                            selected!.bodySource,
                            style: const TextStyle(fontSize: 13, height: 1.7),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed:
                            widget.blocked ||
                                selected!.bodySource.trim().isEmpty
                            ? null
                            : () => widget.onInsert(selected!.relativePath),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('插入到正文'),
                      ),
                    ],
                  ),
          ),
          if (error != null)
            Text(
              error!,
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
        ],
      ),
    );
  }
}
