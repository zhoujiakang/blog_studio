import 'package:blog_studio/platform/contracts/credential_store.dart';
import 'package:blog_studio/platform/macos/credential_store.dart';

import 'dart:io';

import 'package:blog_studio/app/window_options.dart';
import 'package:blog_studio/platform/contracts/desktop_platform.dart';
import 'package:blog_studio/platform/macos/desktop_adapters.dart';
import 'package:blog_studio/platform/macos/editor_host.dart';
import 'package:blog_studio/platform/macos/file_drops.dart';
import 'package:blog_studio/platform/runtime_dependencies.dart';
import 'package:blog_studio/platform/shared/desktop_adapters.dart';

/// Composition root. Future platform implementations are selected here.
class AppDependencies {
  AppDependencies({
    required this.files,
    required this.clipboard,
    required this.window,
    required this.browser,
    required this.runtime,
    required this.processes,
    required this.createEditorHost,
    this.drops = const NoFileDrops(),
    this.credentials = const UnavailableCredentialStore(),
  });
  static AppDependencies get current {
    if (Platform.isMacOS) return macos;
    throw UnsupportedError('此平台尚未提供适配器，目前仅支持 macOS。');
  }

  static final macos = AppDependencies(
    files: PluginFileDialogs(),
    clipboard: PluginClipboardImages(),
    window: MacDesktopWindow(options: studioWindowOptions),
    browser: PluginExternalBrowser(),
    runtime: RuntimeDependencies.platform,
    processes: RuntimeDependencies.processes,
    createEditorHost: MacEditorHost.new,
    drops: MacFileDrops(),
    credentials: const MacCredentialStore(),
  );
  final CredentialStore credentials;
  final FileDialogs files;
  final FileDrops drops;
  final ClipboardImages clipboard;
  final DesktopWindow window;
  final ExternalBrowser browser;
  final RuntimePlatform runtime;
  final ProcessRunner processes;
  final EditorHost Function() createEditorHost;
}
