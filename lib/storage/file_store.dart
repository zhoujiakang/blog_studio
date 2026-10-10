import 'package:blog_studio/platform/runtime_dependencies.dart';
import 'package:blog_studio/platform/contracts/runtime_platform.dart';

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:blog_studio/models/studio_exception.dart';
import 'package:blog_studio/storage/path_guard.dart';

String contentHash(List<int> bytes) => sha256.convert(bytes).toString();

class FileStore {
  FileStore(this.guard, {ProcessRunner? processes})
    : processes = processes ?? RuntimeDependencies.processes;
  final ProcessRunner processes;
  final PathGuard guard;
  Future<void> _tail = Future.value();
  Future<T> serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<Uint8List> read(String relative) async =>
      File(await guard.resolve(relative)).readAsBytes();

  Future<String> write(
    String relative,
    List<int> bytes, {
    required String? expectedHash,
  }) => serial(() async {
    final file = File(await guard.resolve(relative));
    final exists = await file.exists();
    if ((exists && contentHash(await file.readAsBytes()) != expectedHash) ||
        (!exists && expectedHash != null)) {
      throw const StudioException(
        StudioError.fileConflict,
        '文件已在外部修改或删除，当前输入已保留。',
      );
    }
    await file.parent.create(recursive: true);
    if (!exists) {
      // Exclusive reservation makes new article names collision-safe.
      await file.create(exclusive: true);
    }
    final temp = File(
      '${file.path}.studio-${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    var committed = false;
    try {
      await temp.writeAsBytes(bytes, flush: true);
      if (exists) {
        final original = await file.readAsBytes();
        if (contentHash(original) != expectedHash) {
          throw const StudioException(
            StudioError.fileConflict,
            '保存期间原文件已变化，当前输入已保留。',
          );
        }
        final backup = File(
          await guard.resolve('.blog-studio/backups/$relative'),
        );
        await backup.parent.create(recursive: true);
        await backup.writeAsBytes(original, flush: true);
        // Keep the original mode when replacing the inode on macOS.
        await processes.preserveFileMode(file.path, temp.path);
        if (contentHash(await file.readAsBytes()) != expectedHash) {
          throw const StudioException(
            StudioError.fileConflict,
            '保存期间检测到外部修改，未覆盖。',
          );
        }
      }
      await temp.rename(file.path);
      committed = true;
      return contentHash(bytes);
    } finally {
      if (await temp.exists()) await temp.delete();
      if (!exists &&
          !committed &&
          await file.exists() &&
          await file.length() == 0) {
        await file.delete();
      }
    }
  });

  Future<void> move(String from, String to, String hash) => serial(() async {
    final source = File(await guard.resolve(from));
    final target = File(await guard.resolve(to));
    if (contentHash(await source.readAsBytes()) != hash) {
      throw const StudioException(StudioError.fileConflict, '原文件已变化，请重新加载后操作。');
    }
    await target.parent.create(recursive: true);
    try {
      await target.create(exclusive: true);
    } on FileSystemException {
      throw const StudioException(StudioError.fileConflict, '目标已有同名文件，未覆盖。');
    }
    try {
      await source.rename(target.path);
    } catch (_) {
      if (await target.exists() && await target.length() == 0) {
        await target.delete();
      }
      rethrow;
    }
  });
}
