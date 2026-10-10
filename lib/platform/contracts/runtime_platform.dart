import 'dart:io';

abstract interface class RuntimePlatform {
  List<String> get commonPaths;
  List<String> searchPaths(Map<String, String> environment);
  Map<String, String> processEnvironment(
    String node,
    Map<String, String> environment,
  );
  Directory get runtimeDirectory;
  Future<String> architecture();
  String get archiveTool;
  String archiveName(String folder);
  List<String> archiveListingArguments(String archive);
  List<String> archiveExtractionArguments(String archive, String destination);
  String get packagePlatform;
  String releaseFile(String arch);
  String nodePath(String directory);
  String npmPath(String directory);
  bool isRuntimeFolder(String name);
}

abstract interface class ProcessRunner {
  Future<Process> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  });
  Future<ProcessResult> run(String executable, List<String> arguments);
  bool terminate(Process process, {bool force = false});
  Future<void> preserveFileMode(String source, String target);
}
