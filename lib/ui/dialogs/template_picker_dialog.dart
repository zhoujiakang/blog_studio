import 'package:flutter/material.dart';

import 'package:blog_studio/models/blog_template.dart';

class TemplatePickerDialog extends StatefulWidget {
  const TemplatePickerDialog({
    super.key,
    required this.root,
    required this.templates,
  });
  final String root;
  final List<BlogTemplate> templates;
  @override
  State<TemplatePickerDialog> createState() => _TemplatePickerDialogState();
}

class _TemplatePickerDialogState extends State<TemplatePickerDialog> {
  late String selected = widget.templates.first.id;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('选择博客模板'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('选择一种风格，从 GitHub 下载到当前空目录。'),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: widget.templates.length,
              separatorBuilder: (_, index) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final template = widget.templates[index];
                return ListTile(
                  title: Text(template.name),
                  leading: const Icon(Icons.article_outlined),
                  trailing: selected == template.id
                      ? const Icon(Icons.check)
                      : null,
                  selected: selected == template.id,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onTap: () => setState(() => selected = template.id),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Text(widget.root, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, selected),
        child: const Text('创建博客'),
      ),
    ],
  );
}
