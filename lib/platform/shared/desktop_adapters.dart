import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'package:blog_studio/models/image.dart';
import 'package:blog_studio/storage/image_importer.dart';
import 'package:blog_studio/platform/contracts/desktop_platform.dart';
import 'package:blog_studio/platform/shared/clipboard_images.dart';

class PluginFileDialogs implements FileDialogs {
  @override
  Future<String?> chooseBlogDirectory() =>
      getDirectoryPath(confirmButtonText: '打开目录', canCreateDirectories: true);
  @override
  Future<ImageInput?> chooseImage({String label = '图片'}) async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: label,
          extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
          uniformTypeIdentifiers: ['public.image'],
        ),
      ],
    );
    return file == null ? null : await ImageImporter.readFile(file.path);
  }
}

class PluginClipboardImages implements ClipboardImages {
  @override
  Future<ImageInput?> readImage() => readClipboardImage();
  @override
  Future<void> writeText(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

abstract class PluginDesktopWindow
    with WindowListener
    implements DesktopWindow {
  PluginDesktopWindow({required this.options});
  final WindowOptions options;
  final Set<VoidCallback> _callbacks = {};
  @override
  Future<void> initialize() async {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  @override
  void watchClose(VoidCallback callback) {
    if (_callbacks.isEmpty) {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
    }
    _callbacks.add(callback);
  }

  @override
  void unwatchClose(VoidCallback callback) {
    _callbacks.remove(callback);
    if (_callbacks.isEmpty) {
      windowManager.removeListener(this);
      windowManager.setPreventClose(false);
    }
  }

  @override
  void onWindowClose() {
    for (final callback in _callbacks.toList()) {
      callback();
    }
  }
}

class PluginExternalBrowser implements ExternalBrowser {
  @override
  Future<void> open(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw StateError('无法打开浏览器');
    }
  }
}
