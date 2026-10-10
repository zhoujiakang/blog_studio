import 'package:flutter/services.dart';
import 'package:blog_studio/platform/shared/desktop_adapters.dart';

/// Only the native quit request is macOS-specific. Close listeners are shared.
class MacDesktopWindow extends PluginDesktopWindow {
  MacDesktopWindow({required super.options});

  @override
  Future<void> quit() =>
      const MethodChannel('blog_studio/lifecycle').invokeMethod<void>('quit');
}
