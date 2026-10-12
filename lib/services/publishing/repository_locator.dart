import 'dart:io';

import 'package:blog_studio/models/publishing.dart';
import 'package:blog_studio/storage/file_store.dart';

/// Only the current blog's own origin is a suggestion, never its parent repo.
class RepositoryLocator {
  Future<PublishTarget?> detect(FileStore store) async {
    try {
      final file = File(await store.guard.resolve('.git/config'));
      if (!await file.exists() || await file.length() > 65536) return null;
      var origin = false;
      for (final line in (await file.readAsString()).split('\n')) {
        final text = line.trim();
        if (text.startsWith('[')) {
          origin = text == '[remote "origin"]';
        } else if (origin) {
          final match = RegExp(r'^url\s*=\s*(.+)$').firstMatch(text);
          if (match != null) return PublishTarget.fromUrl(match.group(1)!);
        }
      }
    } on FileSystemException {
      return null;
    } on PublishingException {
      return null;
    } catch (_) {
      // Unreadable, linked or unsupported Git metadata is not a blog error.
      return null;
    }
    return null;
  }
}
