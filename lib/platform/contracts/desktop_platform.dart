export 'package:blog_studio/platform/contracts/runtime_platform.dart';

import 'package:flutter/material.dart';
import 'package:blog_studio/models/image.dart';

abstract interface class FileDialogs {
  Future<String?> chooseBlogDirectory();
  Future<ImageInput?> chooseImage({String label = '图片'});
}

abstract interface class ClipboardImages {
  Future<ImageInput?> readImage();
  Future<void> writeText(String text);
}

abstract interface class DesktopWindow {
  Future<void> initialize();
  void watchClose(VoidCallback callback);
  void unwatchClose(VoidCallback callback);
  Future<void> quit();
}

abstract interface class ExternalBrowser {
  Future<void> open(Uri url);
}

abstract interface class EditorHost {
  Widget buildView();
  Future<void> load(
    String html, {
    required void Function(String) onMessage,
    required void Function(String) onError,
    required VoidCallback onPasteImage,
  });
  Future<void> execute(String script);
  Future<Object> evaluate(String script);
  Future<bool> focus();
  Future<void> releaseKeyboard();
  Future<Map<dynamic, dynamic>?> focusState();
  void dispose();
}

class FileDropEvent {
  const FileDropEvent({this.hovering = false, this.paths = const []});
  final bool hovering;
  final List<String> paths;
}

abstract interface class FileDrops {
  void watch(void Function(FileDropEvent) onEvent);
  void unwatch();
  Future<void> setTarget(Rect? rectangle);
}

class NoFileDrops implements FileDrops {
  const NoFileDrops();
  @override
  void watch(void Function(FileDropEvent) onEvent) {}
  @override
  void unwatch() {}
  @override
  Future<void> setTarget(Rect? rectangle) async {}
}
