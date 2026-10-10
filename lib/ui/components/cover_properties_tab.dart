import 'package:blog_studio/storage/resource_layout.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:blog_studio/ui/components/property_bindings.dart';

import 'package:blog_studio/ui/theme/property_style.dart';

class CoverPropertiesTab extends StatefulWidget {
  const CoverPropertiesTab({super.key, required this.data});
  final PropertyBindings data;
  @override
  State<CoverPropertiesTab> createState() => _CoverPropertiesTabState();
}

class _CoverPropertiesTabState extends State<CoverPropertiesTab> {
  Future<Uint8List?>? _coverBytes;
  @override
  void initState() {
    super.initState();
    _coverBytes = _readCover();
  }

  @override
  void didUpdateWidget(covariant CoverPropertiesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.values['cover'] != widget.data.values['cover']) {
      _coverBytes = _readCover();
    }
  }

  Future<Uint8List?> _readCover() async {
    final url = widget.data.values['cover']?.toString() ?? '';
    if (!url.startsWith('/img/')) return null;
    try {
      return await widget.data.store.read(
        ResourceLayout(widget.data.store.guard.root).imagePath(url),
      );
    } catch (_) {
      return null;
    }
  }

  Widget _cover() {
    final value = widget.data.values['cover']?.toString() ?? '';
    Widget placeholder(String text) => ColoredBox(
      color: const Color(0xfff4f4f4),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.image_outlined,
              size: 28,
              color: Color(0xffaaaaaa),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              style: propertyTextStyle.copyWith(
                fontSize: 12,
                color: const Color(0xff999999),
              ),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: FutureBuilder<Uint8List?>(
              future: _coverBytes,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes == null) {
                  return placeholder(value.isEmpty ? '为文章添加封面' : '封面暂时无法显示');
                }
                return value.toLowerCase().endsWith('.svg')
                    ? SvgPicture.memory(
                        bytes,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => placeholder('封面暂时无法显示'),
                      )
                    : Image.memory(
                        bytes,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => placeholder('封面暂时无法显示'),
                      );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: widget.data.importing ? null : widget.data.onPickCover,
          icon: Icon(
            widget.data.importing
                ? Icons.hourglass_empty
                : Icons.folder_open_outlined,
            size: 16,
          ),
          label: Text(
            widget.data.importing
                ? '正在添加…'
                : value.isEmpty
                ? '选择封面图片'
                : '更换封面图片',
            style: propertyTextStyle,
          ),
        ),
        if (value.isNotEmpty)
          TextButton(
            onPressed: widget.data.importing
                ? null
                : () => widget.data.onChanged({'cover': ''}),
            child: Text(
              '移除封面',
              style: propertyTextStyle.copyWith(
                fontSize: 12,
                color: const Color(0xff888888),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => _cover();
}
