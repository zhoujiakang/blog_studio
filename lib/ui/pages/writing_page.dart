import 'package:blog_studio/controllers/web_markdown_controller.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:blog_studio/controllers/studio_controller.dart';
import 'package:blog_studio/services/editor_session.dart';

import 'package:blog_studio/ui/components/file_drop_area.dart';

import 'package:blog_studio/ui/components/web_markdown_editor.dart';
import 'package:blog_studio/ui/components/notes_reference.dart';

import 'package:blog_studio/models/save_state.dart';
import 'package:blog_studio/ui/components/article_properties.dart';

class WritingPage extends StatelessWidget {
  const WritingPage({super.key, required this.controller});
  final StudioController controller;
  EditorSession get session => controller.session;
  bool get noteReference => controller.noteReference;
  set noteReference(bool value) => controller.noteReference = value;
  bool get properties => controller.properties;
  set properties(bool value) => controller.properties = value;
  bool get dragging => controller.dragging;
  set dragging(bool value) => controller.dragging = value;
  String get _saveLabel => switch (session.status) {
    SaveStatus.clean => '已保存',
    SaveStatus.dirty => '待保存',
    SaveStatus.saving => '保存中…',
    SaveStatus.failed => '保存失败',
    SaveStatus.conflict => '外部修改冲突',
  };
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            IconButton(
              tooltip: session.article!.about
                  ? '返回'
                  : session.article!.note
                  ? '返回小记'
                  : '返回文章',
              onPressed: controller.returnToLibrary,
              icon: const Icon(Icons.arrow_back, size: 20),
            ),
            Expanded(
              child: Text(
                session.article!.about
                    ? '关于'
                    : session.article!.note
                    ? '小记 · ${session.attributes['date'] ?? ''}'
                    : session.attributes['title']?.toString() ?? '未命名文章',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                ),
              ),
            ),
            Text(
              _saveLabel,
              style: TextStyle(
                fontSize: 12,
                color: session.error == null
                    ? const Color(0xff888888)
                    : Colors.red,
              ),
            ),
            IconButton(
              tooltip: '保存 · ⌘S',
              onPressed: () => session.flush(),
              icon: const Icon(Icons.save_outlined, size: 20),
            ),
            IconButton(
              tooltip: '插入图片',
              onPressed: session.importing ? null : controller.pickImage,
              icon: const Icon(Icons.image_outlined, size: 20),
            ),
            if (session.article!.post)
              IconButton(
                tooltip: '小记参考',
                onPressed: () => controller.update(() {
                  noteReference = !noteReference;
                  properties = false;
                }),
                icon: const Icon(Icons.notes_outlined, size: 20),
              ),
            if (session.article!.post)
              IconButton(
                tooltip: '文章属性',
                onPressed: () => controller.update(() {
                  properties = !properties;
                  noteReference = false;
                }),
                icon: const Icon(Icons.tune, size: 20),
              ),
          ],
        ),
      ),
      if (session.error != null)
        Container(
          color: const Color(0xfffff6f1),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  session.error!,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: () => session.flush(),
                child: const Text('重试'),
              ),
              TextButton(
                onPressed: controller.reloadDocument,
                child: const Text('重新加载'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await controller.copy();
                  } catch (e) {
                    controller.prompts.message('$e');
                  }
                },
                child: const Text('复制正文'),
              ),
            ],
          ),
        ),
      const Divider(height: 1, color: Color(0xffeeeeee)),
      Expanded(
        child: Row(
          children: [
            Expanded(
              child: FileDropArea(
                adapter: controller.dependencies.drops,
                onEvent: controller.handleFileDrop,
                child: Stack(
                  children: [
                    WebMarkdownEditor(
                      controller: session.editor as WebMarkdownController,
                      createHost: controller.dependencies.createEditorHost,
                    ),
                    if (dragging)
                      const Positioned.fill(
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: Color(0x22444444),
                            child: Center(child: Text('松开以插入图片')),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (noteReference && session.article!.post)
              SizedBox(
                width: 288,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(left: BorderSide(color: Color(0xffeeeeee))),
                  ),
                  child: NotesReference(
                    notes: session.notes,
                    repository: session.repository!,
                    onFocus: () => unawaited(session.editor.releaseKeyboard()),
                    blocked: session.busy || session.importing,
                    onInsert: (path) async {
                      await session.insertNote(path);
                      if (session.error != null) {
                        controller.prompts.message(session.error!);
                      }
                    },
                  ),
                ),
              ),
            if (properties && session.article!.post)
              SizedBox(
                width: 288,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(left: BorderSide(color: Color(0xffeeeeee))),
                  ),
                  child: ArticleProperties(
                    onFocus: () => unawaited(session.editor.releaseKeyboard()),
                    key: ValueKey(session.article!.relativePath),
                    values: session.attributes,
                    onChanged: session.updateAttributes,
                    articles: session.index.articles,
                    pins: session.taxonomy?.pins ?? const {},
                    onPin: session.toggleTaxonomyPin,
                    onPickCover: controller.pickCover,
                    importing: session.importing,
                    store: session.repository!.store,
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
