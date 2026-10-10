import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Future<Directory> temporaryProject() async {
  final directory = await Directory.systemTemp.createTemp('blog-studio-test-');
  addTearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });
  for (final child in [
    'resource/posts',
    'resource/drafts',
    'resource/images/articles',
  ]) {
    await Directory('${directory.path}/$child').create(recursive: true);
  }
  await Directory('${directory.path}/template/butterfly')
      .create(recursive: true);
  await File(
    '${directory.path}/blog.json',
  ).writeAsString('{"formatVersion":2,"activeTemplate":"butterfly","site":{}}');
  await File('${directory.path}/template/butterfly/package.json')
      .writeAsString('{"engines":{"node":">=22.18.0"}}');
  return directory;
}
