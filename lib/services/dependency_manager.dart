import 'dart:convert';

import 'package:blog_studio/models/dependency_report.dart';
import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/models/runtime_environment.dart';
import 'package:blog_studio/models/studio_exception.dart';
import 'package:blog_studio/services/runtime_detector.dart';

class DependencyManager {
  DependencyManager({required this.probePath, required this.runtimeDetector});
  final String probePath;
  final RuntimeDetector runtimeDetector;
  Future<DependencyReport> inspect(
    ProjectSession project,
    RuntimeEnvironment runtime,
  ) async {
    if (runtime.status != RuntimeStatus.ready) {
      throw const StudioException(StudioError.runtimeMissing, '运行环境尚未准备好。');
    }
    final process = await runtimeDetector.processes.start(
      runtime.nodePath!,
      [probePath, project.root, runtime.npmPath!],
      environment: runtimeDetector.subprocessEnvironment(runtime.nodePath!),
      includeParentEnvironment: false,
    );
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.drain<void>();
    try {
      await process.exitCode.timeout(const Duration(seconds: 15));
      await stderr;
      final result = jsonDecode(await stdout) as Map;
      return DependencyReport(
        status: DependencyStatus.values.byName(result['status'] as String),
        manifestHash: result['manifestHash']?.toString() ?? '',
        lockHash: result['lockHash'] as String?,
        missing: (result['missing'] as List? ?? []).cast<String>(),
        reason: result['reason'] as String?,
      );
    } catch (_) {
      runtimeDetector.processes.terminate(process, force: true);
      return const DependencyReport(
        status: DependencyStatus.broken,
        manifestHash: '',
        reason: '依赖健康检查失败或超时。',
      );
    }
  }
}
