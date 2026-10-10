import 'dart:io';

import 'package:blog_studio/platform/contracts/runtime_platform.dart';
import 'package:blog_studio/platform/macos/runtime_platform.dart';

/// Pure Dart composition for CLI tools and runtime services.
class RuntimeDependencies {
  static final RuntimePlatform platform = _platform();
  static RuntimePlatform _platform() {
    if (Platform.isMacOS) return MacRuntimePlatform();
    throw UnsupportedError('预览环境尚未提供此平台的适配器。');
  }

  static final ProcessRunner processes = MacProcessRunner();
}
