import 'package:flutter/material.dart';

class NewArticleDialog extends StatefulWidget {
  const NewArticleDialog({super.key});
  @override
  State<NewArticleDialog> createState() => NewArticleDialogState();
}

class NewArticleDialogState extends State<NewArticleDialog> {
  final title = TextEditingController();
  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('新建文章'),
    content: TextField(
      controller: title,
      autofocus: true,
      decoration: const InputDecoration(hintText: '文章标题'),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, title.text),
        child: const Text('创建草稿'),
      ),
    ],
  );
}
