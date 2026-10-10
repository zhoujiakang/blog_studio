import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:blog_studio/services/editor_session.dart';
import 'package:blog_studio/models/save_state.dart';
import 'package:blog_studio/storage/resource_layout.dart';
import 'package:blog_studio/storage/template_configuration.dart';

class TemplateConfigurationPage extends StatelessWidget {
  const TemplateConfigurationPage({
    super.key,
    required this.session,
    required this.onSwitch,
    this.onPickImage,
  });
  final EditorSession session;
  final VoidCallback onSwitch;
  final Future<void> Function(String)? onPickImage;
  @override
  Widget build(BuildContext context) {
    final config = session.configuration!;
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '主题配置',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: session.busy ? null : onSwitch,
              child: const Text('切换模板'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '当前模板 · ${config.name}',
          style: const TextStyle(color: Color(0xff777777)),
        ),
        const SizedBox(height: 28),
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final field in config.fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 28),
                    child: _ConfigurationField(
                      key: ValueKey('${config.path}/${field['key']}'),
                      session: session,
                      onPickImage: onPickImage,
                      config: config,
                      field: field,
                    ),
                  ),
                if (session.error != null) ...[
                  Text(
                    session.error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: session.reloadConfiguration,
                      child: const Text('重新加载磁盘配置'),
                    ),
                  ),
                ],
                Row(
                  children: [
                    FilledButton(
                      onPressed: session.busy ? null : () => session.flush(),
                      child: const Text('保存配置'),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: session.busy
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('恢复默认配置？'),
                                  content: const Text('只恢复当前模板的设置，文章和图片文件会保留。'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('恢复默认'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                session.resetConfiguration();
                              }
                            },
                      child: const Text('恢复默认'),
                    ),
                    const Spacer(),
                    Text(
                      session.status == SaveStatus.conflict
                          ? '保存冲突'
                          : session.status == SaveStatus.failed
                          ? '保存失败'
                          : session.dirty
                          ? '等待保存…'
                          : '已保存',
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

class _ConfigurationField extends StatefulWidget {
  const _ConfigurationField({
    super.key,
    required this.session,
    required this.config,
    required this.field,
    this.onPickImage,
  });
  final EditorSession session;
  final TemplateConfiguration config;
  final Map<String, dynamic> field;
  final Future<void> Function(String)? onPickImage;
  @override
  State<_ConfigurationField> createState() => _ConfigurationFieldState();
}

class _ConfigurationFieldState extends State<_ConfigurationField> {
  late final controller = TextEditingController(
    text: widget.config.value(widget.field),
  );
  String get value => widget.config.value(widget.field);
  String get fieldKey => widget.field['key'] as String;
  void change(String next) =>
      widget.session.updateConfiguration(fieldKey, next);
  @override
  void didUpdateWidget(covariant _ConfigurationField old) {
    super.didUpdateWidget(old);
    if (value != old.config.value(old.field) && controller.text != value) {
      controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> pickImage() async => widget.onPickImage?.call(fieldKey);

  Future<Uint8List> readImage() => widget.session.repository!.store.read(
    ResourceLayout(widget.session.project!.root).imagePath(value),
  );
  Future<void> pickColor() async {
    var hsv = HSVColor.fromColor(
      Color(int.parse(value.substring(1), radix: 16) | 0xff000000),
    );
    final chosen = await showDialog<Color>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(widget.field['label']),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 72,
                  decoration: BoxDecoration(
                    color: hsv.toColor(),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(height: 20),
                for (final item in ['色相', '饱和度', '明度'])
                  Row(
                    children: [
                      SizedBox(width: 60, child: Text(item)),
                      Expanded(
                        child: Slider(
                          value: item == '色相'
                              ? hsv.hue / 360
                              : item == '饱和度'
                              ? hsv.saturation
                              : hsv.value,
                          onChanged: (v) => setState(() {
                            hsv = item == '色相'
                                ? hsv.withHue(v * 360)
                                : item == '饱和度'
                                ? hsv.withSaturation(v)
                                : hsv.withValue(v);
                          }),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, hsv.toColor()),
              child: const Text('使用此颜色'),
            ),
          ],
        ),
      ),
    );
    if (chosen != null && mounted) {
      change(
        '#${(chosen.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.field['type'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.field['label'],
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        if (widget.field['description'] is String)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              widget.field['description'],
              style: const TextStyle(color: Color(0xff888888), fontSize: 12),
            ),
          ),
        const SizedBox(height: 10),
        if (type == 'text')
          TextField(
            controller: controller,
            enabled: !widget.session.busy,
            minLines: widget.field['multiline'] == true ? 3 : 1,
            maxLines: widget.field['multiline'] == true ? 6 : 1,
            onChanged: change,
          ),
        if (type == 'image') ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 180,
              width: double.infinity,
              color: const Color(0xfff5f5f5),
              child: value.isEmpty
                  ? const Center(
                      child: Icon(
                        Icons.image_outlined,
                        color: Color(0xffaaaaaa),
                        size: 36,
                      ),
                    )
                  : FutureBuilder<Uint8List>(
                      future: readImage(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return Center(
                            child: Text(
                              snapshot.hasError ? '图片不可用，请重新选择' : '正在加载图片',
                              style: const TextStyle(color: Color(0xff888888)),
                            ),
                          );
                        }
                        return value.toLowerCase().endsWith('.svg')
                            ? SvgPicture.memory(
                                snapshot.data!,
                                fit: BoxFit.cover,
                              )
                            : Image.memory(snapshot.data!, fit: BoxFit.cover);
                      },
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: widget.session.busy || widget.session.importing
                    ? null
                    : pickImage,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('选择图片'),
              ),
              const SizedBox(width: 8),
              if (value.isNotEmpty)
                TextButton(
                  onPressed: widget.session.busy ? null : () => change(''),
                  child: const Text('移除'),
                ),
            ],
          ),
        ],
        if (type == 'color')
          Row(
            children: [
              InkWell(
                onTap: widget.session.busy ? null : pickColor,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 48,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Color(
                      int.parse(value.substring(1), radix: 16) | 0xff000000,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xffdddddd)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 150,
                child: TextField(
                  controller: controller,
                  enabled: !widget.session.busy,
                  decoration: InputDecoration(
                    hintText: '#RRGGBB',
                    errorText:
                        RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(controller.text)
                        ? null
                        : '请输入六位颜色',
                  ),
                  onChanged: (v) {
                    setState(() {});
                    if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v)) change(v);
                  },
                  onEditingComplete: () {
                    controller.text = value;
                    FocusScope.of(context).unfocus();
                  },
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: widget.session.busy ? null : pickColor,
                child: const Text('选择颜色'),
              ),
            ],
          ),
        if (!['text', 'image', 'color'].contains(type))
          const Text(
            '当前应用不支持此配置类型，保存时会保留原值。',
            style: TextStyle(color: Color(0xff888888)),
          ),
      ],
    );
  }
}
