import 'dart:io';

import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/models/runtime_environment.dart';
import 'package:blog_studio/services/runtime_detector.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

Future<String> executable(
  Directory root,
  String name,
  String script, {
  bool allowExecute = true,
}) async {
  final file = File('${root.path}/$name');
  await file.writeAsString('#!/bin/sh\n$script\n');
  await Process.run('/bin/chmod', [allowExecute ? '700' : '600', file.path]);
  return file.path;
}

void main() {
  test('empty PATH reports missing without installing or writing', () async {
    final root = await temporaryProject();
    final detector = RuntimeDetector(
      environment: const {'PATH': ''},
      commonPaths: const [],
    );
    final result = await detector.detect(ProjectSession(root: root.path));
    expect(result.status, RuntimeStatus.missing);
    expect(await Directory('${root.path}/node_modules').exists(), false);
  });
  test(
    'common paths discover actual executables with isolated process PATH',
    () async {
      final root = await temporaryProject();
      await File('${root.path}/template/butterfly/package.json')
          .writeAsString('{"engines":{"node":">=22.18.0"}}');
      await executable(root, 'node', 'echo v22.21.1');
      await executable(root, 'npm', 'echo 10.9.4');
      final detector = RuntimeDetector(
        environment: const {'PATH': ''},
        commonPaths: [root.path],
      );
      final result = await detector.detect(ProjectSession(root: root.path));
      expect(result.status, RuntimeStatus.ready);
      expect(
        result.nodePath,
        await File('${root.path}/node').resolveSymbolicLinks(),
      );
      expect(
        detector.subprocessEnvironment(result.nodePath!)['PATH'],
        startsWith(await root.resolveSymbolicLinks()),
      );
    },
  );
  test(
    'old version, permission failure and timeout are distinguished',
    () async {
      final root = await temporaryProject();
      await File('${root.path}/template/butterfly/package.json')
          .writeAsString('{"engines":{"node":">=22.18.0"}}');
      await executable(root, 'node', 'echo v18.20.0');
      await executable(root, 'npm', 'echo 10.9.4');
      final detector = RuntimeDetector(
        environment: const {'PATH': ''},
        commonPaths: [root.path],
        timeout: const Duration(seconds: 1),
      );
      expect(
        (await detector.detect(ProjectSession(root: root.path))).status,
        RuntimeStatus.incompatible,
      );
      await executable(root, 'node', 'echo v22.21.1', allowExecute: false);
      expect(
        (await detector.detect(ProjectSession(root: root.path))).status,
        RuntimeStatus.inaccessible,
      );
      await executable(root, 'node', 'exec /bin/sleep 5');
      expect(
        (await detector.detect(ProjectSession(root: root.path))).reason,
        contains('超时'),
      );
    },
  );
}
