import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

Future<void> main(List<String> args) async {
  final pubspec = loadYaml(await File('pubspec.yaml').readAsString()) as Map;
  final version = Version.parse(pubspec['version'] as String);
  final release =
      '${version.major}.${version.minor}.${version.patch}'
      '${version.preRelease.isEmpty ? '' : '-${version.preRelease.join('.')}'}';
  final number = version.build.isEmpty ? '1' : version.build.join('.');
  if (!RegExp(r'^\d+$').hasMatch(number)) {
    throw const FormatException('应用构建号必须是整数。');
  }
  final output = {
    '--release': release,
    '--build-name': '${version.major}.${version.minor}.${version.patch}',
    '--build-number': number,
  };
  for (final flag in output.keys) {
    if (args.contains(flag)) {
      stdout.writeln(output[flag]);
      return;
    }
  }
  await File('lib/app/app_version.dart').writeAsString(
    '''// Generated from pubspec.yaml by tool/generate_app_version.dart.
abstract final class AppVersion {
  static const version = '$release';
  static const buildNumber = '$number';
  static const buildName = '${version.major}.${version.minor}.${version.patch}';
}
''',
  );
}
