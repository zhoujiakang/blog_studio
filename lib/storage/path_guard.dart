import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:blog_studio/models/studio_exception.dart';

class PathGuard {
  PathGuard(this.root);
  final String root;
  Future<String> resolve(String relative) async {
    if (p.isAbsolute(relative) ||
        relative.contains('\\') ||
        relative
            .split('/')
            .any((part) => part == '..' || part == '.' || part.isEmpty)) {
      throw const StudioException(StudioError.invalidProject, '路径必须位于当前博客目录内。');
    }
    final base = await Directory(root).resolveSymbolicLinks();
    final target = p.joinAll([base, ...relative.split('/')]);
    if (!p.isWithin(base, target)) {
      throw const StudioException(StudioError.invalidProject, '不能访问博客目录外的文件。');
    }
    var current = base;
    for (final part in relative.split('/')) {
      current = p.join(current, part);
      if (await FileSystemEntity.type(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const StudioException(
          StudioError.invalidProject,
          '博客内的符号链接不能用于编辑。',
        );
      }
    }
    return target;
  }
}
