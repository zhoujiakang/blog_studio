import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blog_studio/services/managed_runtime.dart';
import 'package:blog_studio/services/runtime_detector.dart';
import 'package:blog_studio/models/project.dart';

/// Explicit developer verification: downloads an official portable runtime in
/// a temporary support folder and exercises an independent fixture, never user content.
Future<void> main(List<String> args) async {
  if (!args.contains('--allow-download')) {
    stderr.writeln('需要 --allow-download 授权本次真实下载验证。');
    exitCode = 1;
    return;
  }
  final fixture =
      jsonDecode(await File('build/test-blog.json').readAsString()) as Map;
  final temp = await Directory.systemTemp.createTemp(
    'studio-real-managed-runtime-',
  );
  Process? server;
  try {
    final detector = RuntimeDetector(
      environment: const {'PATH': '/usr/bin:/bin'},
      commonPaths: const [],
    );
    final managed = ManagedRuntime(
      directory: Directory('${temp.path}/runtimes'),
    );
    var last = '';
    final runtime = await managed.install(
      ProjectSession(root: fixture['root']),
      detector,
      (message, _) {
        final stage = message.split(' · ').first;
        if (stage != last) {
          last = stage;
          stdout.writeln(stage);
        }
      },
    );
    stdout.writeln('官方运行组件已校验并启动：${runtime.nodeVersion}');
    final cached = await managed.detect(
      ProjectSession(root: fixture['root']),
      detector,
    );
    if (cached == null) throw StateError('缓存复用失败');
    server = await Process.start(
      runtime.nodePath!,
      [File('integrations/preview/server.mjs').absolute.path, fixture['root']],
      environment: detector.subprocessEnvironment(runtime.nodePath!),
      includeParentEnvironment: false,
    );
    final events = StreamIterator(
      server.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    server.stderr.listen(stderr.add);
    server.stdin.writeln(jsonEncode({'type': 'start', 'request': 1}));
    if (!await events.moveNext().timeout(const Duration(seconds: 45))) {
      throw StateError('预览未启动');
    }
    final ready = jsonDecode(events.current) as Map;
    if (ready['type'] != 'ready') throw StateError(ready.toString());
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(
        Uri.parse('${ready['url']}src/App.vue'),
      )).close();
      if (response.statusCode != 200 ||
          !(await response.transform(utf8.decoder).join()).contains(
            '--accent',
          )) {
        throw StateError('预览入口失败');
      }
    } finally {
      client.close(force: true);
    }
    server.stdin.writeln(jsonEncode({'type': 'stop', 'request': 2}));
    await server.stdin.close();
    await server.exitCode.timeout(const Duration(seconds: 10));
    server = null;
    await events.cancel();
    stdout.writeln('空系统 PATH 下下载、缓存复用和真实 Vue 预览通过。');
  } finally {
    server?.kill(ProcessSignal.sigkill);
    if (server != null) await server.exitCode;
    await temp.delete(recursive: true);
  }
}
