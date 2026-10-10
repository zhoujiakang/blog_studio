import 'package:blog_studio/platform/runtime_dependencies.dart';
import 'package:blog_studio/platform/contracts/runtime_platform.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blog_studio/storage/resource_layout.dart';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/models/runtime_environment.dart';

class RuntimeDetector {
  RuntimeDetector({
    Map<String, String>? environment,
    List<String>? commonPaths,
    RuntimePlatform? platform,
    ProcessRunner? processes,
    this.timeout = const Duration(seconds: 5),
  }) : platform = platform ?? RuntimeDependencies.platform,
       processes = processes ?? RuntimeDependencies.processes,
       commonPaths =
           commonPaths ??
           (platform ?? RuntimeDependencies.platform).commonPaths,
       environment = environment ?? Platform.environment;
  final RuntimePlatform platform;
  final ProcessRunner processes;
  final Map<String, String> environment;
  final List<String> commonPaths;
  final Duration timeout;

  Future<RuntimeEnvironment> detect(
    ProjectSession project, {
    String? nodePath,
    String? npmPath,
  }) async {
    final paths = [...platform.searchPaths(environment), ...commonPaths];
    final node = await _find('node', nodePath, paths);
    final npm = await _find('npm', npmPath, [
      if (node != null) p.dirname(node),
      ...paths,
    ]);
    if (node == null || npm == null) {
      return const RuntimeEnvironment(
        status: RuntimeStatus.missing,
        reason: '未找到 Node.js 或 npm，请安装后重新检测，或选择可执行文件。',
      );
    }
    try {
      final env = subprocessEnvironment(node);
      final nv = await _version(node, env);
      final pv = await _version(npm, env);
      final manifest = jsonDecode(
        await File(
          p.join(ResourceLayout(project.root).packageRoot, 'package.json'),
        ).readAsString(),
      ) as Map;
      final requirement =
          manifest['engines']?['node']?.toString() ?? '>=22.18.0';
      final version = Version.parse(nv.replaceFirst(RegExp(r'^v'), ''));
      final constraint = VersionConstraint.parse(requirement);
      if (!constraint.allows(version)) {
        return RuntimeEnvironment(
          status: RuntimeStatus.incompatible,
          nodePath: node,
          npmPath: npm,
          nodeVersion: nv,
          npmVersion: pv,
          reason: '博客要求 Node.js $requirement，当前版本 $nv。',
        );
      }
      return RuntimeEnvironment(
        status: RuntimeStatus.ready,
        nodePath: node,
        npmPath: npm,
        nodeVersion: nv,
        npmVersion: pv,
      );
    } on TimeoutException {
      return RuntimeEnvironment(
        status: RuntimeStatus.inaccessible,
        nodePath: node,
        npmPath: npm,
        reason: '运行环境检测超时。',
      );
    } catch (_) {
      return RuntimeEnvironment(
        status: RuntimeStatus.inaccessible,
        nodePath: node,
        npmPath: npm,
        reason: '无法读取运行环境版本或博客的 Node.js 版本要求。',
      );
    }
  }

  Map<String, String> subprocessEnvironment(String node) =>
      platform.processEnvironment(node, environment);

  Future<String?> _find(
    String command,
    String? explicit,
    List<String> paths,
  ) async {
    for (final candidate
        in explicit == null
            ? paths
                  .where((s) => s.isNotEmpty)
                  .map((dir) => p.join(dir, command))
            : [explicit]) {
      try {
        if (await File(candidate).exists()) {
          return await File(candidate).resolveSymbolicLinks();
        }
      } on FileSystemException {
        continue;
      }
    }
    return null;
  }

  Future<String> _version(String executable, Map<String, String> env) async {
    final process = await processes.start(
      executable,
      ['--version'],
      environment: env,
      includeParentEnvironment: false,
    );
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.drain<void>();
    try {
      final code = await process.exitCode.timeout(timeout);
      await errors;
      final value = (await output).trim();
      if (code != 0 ||
          !RegExp(r'^v?\d+\.\d+\.\d+(?:[-+][\w.-]+)?$').hasMatch(value)) {
        throw StateError('invalid version');
      }
      return value;
    } on TimeoutException {
      processes.terminate(process, force: true);
      await process.exitCode;
      rethrow;
    }
  }
}
