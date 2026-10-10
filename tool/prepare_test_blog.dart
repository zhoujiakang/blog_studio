import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:blog_studio/services/template_installer.dart';

/// Developer fixture creation. This never uses the application install consent.
Future<void> main(List<String> args) async {
  final root = Directory.current.path;
  final target = await Directory.systemTemp.createTemp(
    'blog-studio-preview-fixture-',
  );
  final installer = TemplateInstaller(
    readAsset: (asset) => File(p.join(root, asset)).readAsBytes(),
  );
  await installer.initialize(target.path, templateId: 'butterfly');
  // Preview tests need content; production initialization always starts empty.
  for (final entity in Directory(
    p.join(root, 'test/fixtures/butterfly/posts'),
  ).listSync()) {
    if (entity is File) {
      await entity.copy(
        p.join(target.path, 'resource/posts', p.basename(entity.path)),
      );
    }
  }
  final packageRoot = p.join(target.path, 'template', 'butterfly');
  if (args.contains('--allow-install')) {
    final hasLock = await File(p.join(packageRoot, 'package-lock.json'))
        .exists();
    final process = await Process.start('npm', [
      hasLock ? 'ci' : 'install',
      '--include=dev',
      if (!hasLock) '--package-lock=false',
      '--ignore-scripts',
      '--no-audit',
      '--no-fund',
    ], workingDirectory: packageRoot);
    process.stdout.listen(stdout.add);
    process.stderr.listen(stderr.add);
    final code = await process.exitCode;
    if (code != 0) {
      stderr.writeln('测试依赖安装失败，夹具保留：${target.path}');
      exitCode = code;
      return;
    }
  }
  final build = Directory(p.join(root, 'build'));
  await build.create(recursive: true);
  await File(p.join(build.path, 'test-blog.json'))
      .writeAsString(jsonEncode({'root': target.path}));
  stdout.writeln('独立测试博客：${target.path}');
  stdout.writeln(
    args.contains('--allow-install') ? '依赖安装结束，仍需健康检查。' : '未授权安装；只复制模板。',
  );
}
