import 'dart:io';

import 'package:blog_studio/platform/contracts/runtime_platform.dart';

/// Dart process creation is shared; termination and permissions remain adapters.
abstract class SystemProcessRunner implements ProcessRunner {
  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) => Process.start(
    executable,
    arguments,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
  );
  @override
  Future<ProcessResult> run(String executable, List<String> arguments) =>
      Process.run(executable, arguments);
}
