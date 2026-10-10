import 'package:flutter/services.dart';
import 'package:blog_studio/platform/contracts/desktop_platform.dart';

/// macOS window drag destination; no transparent view intercepts editor clicks.
class MacFileDrops implements FileDrops {
  static const _channel = MethodChannel('inkjian/file_drops');
  @override
  void watch(void Function(FileDropEvent) onEvent) {
    _channel.setMethodCallHandler((call) async {
      final args = call.arguments as Map? ?? {};
      onEvent(
        FileDropEvent(
          hovering: args['hovering'] == true,
          paths: (args['paths'] as List? ?? []).cast<String>(),
        ),
      );
    });
  }

  @override
  void unwatch() => _channel.setMethodCallHandler(null);

  @override
  Future<void> setTarget(Rect? rectangle) => _channel.invokeMethod(
    'target',
    rectangle == null
        ? null
        : {
            'left': rectangle.left,
            'top': rectangle.top,
            'width': rectangle.width,
            'height': rectangle.height,
          },
  );
}
