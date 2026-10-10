import 'dart:convert';
import 'dart:math';

import 'package:blog_studio/models/publishing.dart';
import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/models/blog_manifest.dart';

class PublicationState {
  const PublicationState({
    required this.workspaceId,
    this.target,
    this.commit,
    this.url,
    this.publishedAt,
    this.pending = false,
  });
  final String workspaceId;
  final PublishTarget? target;
  final String? commit;
  final Uri? url;
  final DateTime? publishedAt;
  final bool pending;
}

class PublishingStore {
  PublishingStore(this.store);
  final FileStore store;
  Future<PublicationState> load() async {
    final manifest = BlogManifest.decode(await store.read('blog.json'));
    final value = manifest['publish'];
    if (value is! Map) {
      final random = Random.secure();
      return PublicationState(
        workspaceId: List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
      );
    }
    if (value['provider'] != 'github-pages' ||
        value['workspaceId'] is! String) {
      throw const PublishingException('博客发布配置无效，请检查 blog.json。');
    }
    final url = value['url'] == null ? null : Uri.tryParse(value['url']);
    return PublicationState(
      workspaceId: value['workspaceId'],
      target: PublishTarget.fromJson(Map<String, dynamic>.from(value)),
      commit: value['commit'] as String?,
      url: url,
      publishedAt: value['publishedAt'] == null
          ? null
          : DateTime.parse(value['publishedAt']),
      pending: value['pending'] == true,
    );
  }

  Future<void> save(PublicationState state) async {
    final bytes = await store.read('blog.json');
    final manifest = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(bytes)) as Map,
    );
    manifest['publish'] = {
      ...state.target!.toJson(),
      'workspaceId': state.workspaceId,
      if (state.commit != null) 'commit': state.commit,
      if (state.url != null) 'url': state.url.toString(),
      if (state.publishedAt != null)
        'publishedAt': state.publishedAt!.toIso8601String(),
      'pending': state.pending,
    };
    await store.write(
      'blog.json',
      utf8.encode('${const JsonEncoder.withIndent('  ').convert(manifest)}\n'),
      expectedHash: contentHash(bytes),
    );
  }
}
