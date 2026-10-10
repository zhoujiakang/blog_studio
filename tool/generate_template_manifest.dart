import 'package:pub_semver/pub_semver.dart';

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:blog_studio/storage/template_configuration.dart';

/// Each direct child directory is one complete Vue blog style.
Future<void> main() async {
  final templates = <Map<String, Object>>[];
  final styles = await Directory('template')
      .list(followLinks: false)
      .where(
        (entity) =>
            entity is Directory && !p.basename(entity.path).startsWith('.'),
      )
      .cast<Directory>()
      .toList();
  styles.sort((a, b) => a.path.compareTo(b.path));
  if (styles.isEmpty) throw const FormatException('template/ 下没有风格目录。');
  for (final style in styles) {
    final id = p.basename(style.path);
    if (!RegExp(r'^[a-zA-Z0-9\u4e00-\u9fff][a-zA-Z0-9_\u4e00-\u9fff-]*$')
        .hasMatch(id)) {
      throw FormatException('模板 ID 请使用字母、数字、下划线或连字符：$id');
    }
    final config = Map<String, dynamic>.from(
      jsonDecode(await File(p.join(style.path, 'template.json')).readAsString())
          as Map,
    );
    TemplateConfiguration.validate(config);
    Version.parse(config['minAppVersion'] as String);
    if (config['id'] != id) throw FormatException('模板 $id 的配置 ID 与目录不一致');
    for (final required in ['package.json', 'template.json', 'src/App.vue']) {
      if (!await FileSystemEntity.isFile(p.join(style.path, required)) &&
          !await FileSystemEntity.isDirectory(p.join(style.path, required))) {
        throw FormatException('模板 $id 缺少 $required。');
      }
    }
    if (await Directory(p.join(style.path, 'resource')).exists()) {
      throw FormatException('模板 $id 不应包含 resource/，用户内容由应用单独创建。');
    }
    final records = <Map<String, Object>>[];
    await for (final entity in style.list(
      recursive: true,
      followLinks: false,
    )) {
      final relative = p.relative(entity.path, from: style.path);
      if (relative
          .split(p.separator)
          .any(
            (s) =>
                (s.startsWith('.') && s != '.gitignore') ||
                ['node_modules', 'dist', 'build'].contains(s),
          )) {
        continue;
      }
      if (entity is! File) continue;
      final bytes = await entity.readAsBytes();
      records.add({
        'path': relative,
        'length': bytes.length,
        'hash': sha256.convert(bytes).toString(),
      });
    }
    records.sort(
      (a, b) => (a['path'] as String).compareTo(b['path'] as String),
    );
    templates.add({
      'id': id,
      'name': config['name'] as String,
      'protocolVersion': 2,
      'minAppVersion': config['minAppVersion'] as String,
      'files': records,
    });
  }
  await Directory('assets/generated').create(recursive: true);
  await File('assets/generated/template-manifest.json').writeAsString(
    const JsonEncoder.withIndent('  ')
        .convert({'version': '2', 'templates': templates}),
  );
  stdout.writeln(
    '${templates.length} styles, ${templates.fold<int>(0, (count, style) => count + (style['files'] as List).length)} template files registered.',
  );
}
