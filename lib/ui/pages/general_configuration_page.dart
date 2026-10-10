import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:blog_studio/storage/resource_layout.dart';
import 'package:blog_studio/services/editor_session.dart';

class GeneralConfigurationPage extends StatelessWidget {
  const GeneralConfigurationPage({
    super.key,
    required this.session,
    this.onPickAvatar,
  });
  final EditorSession session;
  final Future<void> Function()? onPickAvatar;
  @override
  Widget build(BuildContext context) {
    final config = session.generalConfiguration!;
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const Text(
          '通用配置',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        const Text(
          '这些信息由所有主题共用，切换主题后仍然保留。',
          style: TextStyle(color: Color(0xff777777)),
        ),
        const SizedBox(height: 28),
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '头像',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _AvatarPreview(
                      key: ValueKey(
                        '${session.project!.root}/${config.value('avatar')}',
                      ),
                      session: session,
                      value: config.value('avatar'),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OutlinedButton.icon(
                            onPressed: session.busy || session.importing
                                ? null
                                : onPickAvatar,
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 18,
                            ),
                            label: Text(
                              config.value('avatar').isEmpty ? '选择头像' : '更换头像',
                            ),
                          ),
                          if (config.value('avatar').isNotEmpty)
                            TextButton(
                              onPressed: session.busy || session.importing
                                  ? null
                                  : () => session.updateGeneralConfiguration(
                                      'avatar',
                                      '',
                                    ),
                              child: const Text('移除头像'),
                            ),
                          const Text(
                            '用于博客作者头像，切换主题后保留。',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xff888888),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                for (final entry in const {
                  'title': '博客名称',
                  'subtitle': '副标题',
                  'author': '作者',
                  'description': '简介',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: TextFormField(
                      key: ValueKey(
                        '${session.project!.root}/${session.generalGeneration}/${entry.key}',
                      ),
                      initialValue: config.value(entry.key),
                      decoration: InputDecoration(
                        labelText: entry.value,
                        alignLabelWithHint: true,
                      ),
                      minLines: entry.key == 'description' ? 3 : 1,
                      maxLines: entry.key == 'description' ? 5 : 1,
                      onChanged: (value) =>
                          session.updateGeneralConfiguration(entry.key, value),
                    ),
                  ),
                if (session.error != null) ...[
                  Text(
                    session.error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                  TextButton(
                    onPressed: session.reloadGeneralConfiguration,
                    child: const Text('重新加载磁盘配置'),
                  ),
                ],
                Row(
                  children: [
                    FilledButton(
                      onPressed: session.busy ? null : () => session.flush(),
                      child: const Text('保存配置'),
                    ),
                    const Spacer(),
                    Text(
                      session.generalDirty ? '等待保存…' : '已保存',
                      style: const TextStyle(
                        color: Color(0xff888888),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AvatarPreview extends StatefulWidget {
  const _AvatarPreview({super.key, required this.session, required this.value});
  final EditorSession session;
  final String value;
  @override
  State<_AvatarPreview> createState() => _AvatarPreviewState();
}

class _AvatarPreviewState extends State<_AvatarPreview> {
  late final Future<Uint8List> image = Future.sync(
    () => widget.session.repository!.store.read(
      ResourceLayout(widget.session.project!.root).imagePath(widget.value),
    ),
  );

  Widget placeholder({bool unavailable = false}) => Container(
    color: const Color(0xfff3f3f3),
    alignment: Alignment.center,
    child: Icon(
      unavailable ? Icons.broken_image_outlined : Icons.person_outline,
      size: 36,
      color: const Color(0xff999999),
    ),
  );

  @override
  Widget build(BuildContext context) => Semantics(
    label: '博客头像预览',
    child: ClipOval(
      child: SizedBox(
        width: 96,
        height: 96,
        child: widget.value.isEmpty
            ? placeholder()
            : FutureBuilder<Uint8List>(
                future: image,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return Tooltip(
                      message: snapshot.hasError ? '头像不可用，请重新选择' : '正在加载头像',
                      child: placeholder(unavailable: snapshot.hasError),
                    );
                  }
                  return widget.value.toLowerCase().endsWith('.svg')
                      ? SvgPicture.memory(snapshot.data!, fit: BoxFit.cover)
                      : Image.memory(
                          snapshot.data!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) =>
                              placeholder(unavailable: true),
                        );
                },
              ),
      ),
    ),
  );
}
