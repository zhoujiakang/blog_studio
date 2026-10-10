import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:blog_studio/platform/contracts/desktop_platform.dart';

class FileDropArea extends StatefulWidget {
  const FileDropArea({
    super.key,
    required this.adapter,
    required this.onEvent,
    required this.child,
  });
  final FileDrops adapter;
  final void Function(FileDropEvent) onEvent;
  final Widget child;
  @override
  State<FileDropArea> createState() => _FileDropAreaState();
}

class _FileDropAreaState extends State<FileDropArea> {
  Rect? _rectangle;
  @override
  void initState() {
    super.initState();
    widget.adapter.watch((event) {
      if (mounted) widget.onEvent(event);
    });
  }

  Future<void> _target(Rect? rectangle) async {
    try {
      await widget.adapter.setTarget(rectangle);
    } on MissingPluginException {
      /* Widget tests have no native window. */
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final rectangle = box.localToGlobal(Offset.zero) & box.size;
      if (_rectangle == rectangle) return;
      _rectangle = rectangle;
      unawaited(_target(rectangle));
    });
    return widget.child;
  }

  @override
  void dispose() {
    widget.adapter.unwatch();
    unawaited(_target(null));
    super.dispose();
  }
}
