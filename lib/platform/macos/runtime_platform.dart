import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'package:blog_studio/platform/contracts/runtime_platform.dart';
import 'package:blog_studio/platform/shared/process_runner.dart';

class MacRuntimePlatform implements RuntimePlatform {
  @override
  List<String> get commonPaths => const ['/opt/homebrew/bin', '/usr/local/bin'];
  @override
  List<String> searchPaths(Map<String, String> environment) {
    final paths = environment['PATH']?.split(':') ?? <String>[];
    final home = environment['HOME'];
    final nvmRoot =
        environment['NVM_DIR'] ?? (home == null ? null : p.join(home, '.nvm'));
    if (nvmRoot == null || nvmRoot.isEmpty) return paths;
    // Finder does not load shell profiles. Inspect installed versions without
    // sourcing user scripts or changing the system environment.
    final versions = <({Version version, String bin})>[];
    try {
      final directory = Directory(p.join(nvmRoot, 'versions', 'node'));
      if (!directory.existsSync()) return paths;
      for (final entry in directory.listSync(followLinks: false)) {
        if (entry is! Directory) continue;
        final name = p.basename(entry.path);
        if (!RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(name)) continue;
        versions.add((
          version: Version.parse(name.substring(1)),
          bin: p.join(entry.path, 'bin'),
        ));
      }
    } on FileSystemException {
      // An unreadable version manager must not hide other installations.
    }
    versions.sort((a, b) => b.version.compareTo(a.version));
    return [...paths, ...versions.map((entry) => entry.bin)];
  }

  @override
  Map<String, String> processEnvironment(
    String node,
    Map<String, String> environment,
  ) => {
    ...environment,
    'PATH': '${p.dirname(node)}:${environment['PATH'] ?? '/usr/bin:/bin'}',
  };
  @override
  Directory get runtimeDirectory => Directory(
    p.join(
      Platform.environment['HOME']!,
      'Library',
      'Application Support',
      'InkJian',
      'runtimes',
    ),
  );
  @override
  Future<String> architecture() async =>
      (await Process.run('/usr/bin/uname', ['-m'])).stdout.toString().trim() ==
          'arm64'
      ? 'arm64'
      : 'x64';
  @override
  String get archiveTool => '/usr/bin/tar';
  @override
  String archiveName(String folder) => '$folder.tar.gz';
  @override
  List<String> archiveListingArguments(String archive) => ['-tzf', archive];
  @override
  List<String> archiveExtractionArguments(String archive, String destination) =>
      ['-xzf', archive, '-C', destination];
  @override
  String get packagePlatform => 'darwin';
  @override
  String releaseFile(String arch) => 'osx-$arch-tar';
  @override
  String nodePath(String directory) => p.join(directory, 'bin/node');
  @override
  String npmPath(String directory) => p.join(directory, 'bin/npm');
  @override
  bool isRuntimeFolder(String name) =>
      RegExp(r'^node-v\d+\.\d+\.\d+-darwin-(arm64|x64)(-\d+)?$').hasMatch(name);
}

class MacProcessRunner extends SystemProcessRunner {
  @override
  bool terminate(Process process, {bool force = false}) =>
      process.kill(force ? ProcessSignal.sigkill : ProcessSignal.sigterm);
  @override
  Future<void> preserveFileMode(String source, String target) async {
    final mode = ((await File(source).stat()).mode & 0x1ff).toRadixString(8);
    await Process.run('/bin/chmod', [mode, target]);
  }
}
