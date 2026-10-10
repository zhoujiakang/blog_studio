import 'dart:convert';
import 'dart:io';

import 'package:blog_studio/storage/file_store.dart';

class TaxonomyPreferences {
  TaxonomyPreferences(this.store);
  final FileStore store;
  static const file = '.blog-studio/taxonomy-pins.json';
  Map<String, List<String>> pins = {'tags': [], 'categories': []};
  String? _hash;
  Future<void> _tail = Future.value();

  Future<void> load() async {
    try {
      final bytes = await store.read(file);
      final data = jsonDecode(utf8.decode(bytes)) as Map;
      for (final key in pins.keys) {
        pins[key] = (data[key] as List? ?? [])
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .toSet()
            .toList();
      }
      _hash = contentHash(bytes);
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode != 2) rethrow;
    }
  }

  Future<void> toggle(String key, String value) {
    final result = _tail.then((_) async {
      final next = {
        for (final entry in pins.entries) entry.key: [...entry.value],
      };
      if (!next[key]!.remove(value)) next[key]!.add(value);
      final hash = await store.write(
        file,
        utf8.encode(jsonEncode(next)),
        expectedHash: _hash,
      );
      pins = next;
      _hash = hash;
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
