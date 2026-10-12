import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/controllers/publish_controller.dart';
import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/models/publishing.dart';
import 'package:blog_studio/services/publishing/github_pages.dart';
import 'package:blog_studio/services/publishing/repository_locator.dart';
import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/storage/path_guard.dart';

import 'publishing_test.dart' show authorized, FakePages, FakeBuilder, Browser;

class ExistingPages extends FakePages {
  ExistingPages(super.auth);
  String identity = 'c3d8c8fd2e72b515f3160e15c912dd1d';
  @override
  Future<RemoteWebsite> inspect(
    PublishTarget target,
    String workspaceId, {
    String? expectedHead,
  }) async {
    if (workspaceId != identity) throw ExistingBlogPublication(identity);
    return const RemoteWebsite('remote-head', {}, cname: 'blog.example.com');
  }
}

void main() {
  test('repository URL accepts HTTPS and SSH but rejects website and unsafe addresses', () {
    for (final url in [
      'https://github.com/alice/blog',
      'https://github.com/alice/blog.git',
      'git@github.com:alice/blog.git',
      'ssh://git@github.com/alice/blog.git',
    ]) {
      expect(PublishTarget.fromUrl(url).fullName, 'alice/blog');
    }
    for (final url in [
      'https://alice.github.io/blog/',
      'https://github.com/alice/blog/tree/main',
      'https://other.example/alice/blog',
      'https://token@github.com/alice/blog',
      'https://github.com/alice/blog?x=1',
    ]) {
      expect(
        () => PublishTarget.fromUrl(url),
        throwsA(isA<PublishingException>()),
      );
    }
  });

  test(
    'origin detection is read-only and limited to this blog directory',
    () async {
      final root = await Directory.systemTemp.createTemp('binding-config-');
      final store = FileStore(PathGuard(root.path));
      try {
        final file = File('${root.path}/blog.json');
        await file.writeAsString(
          jsonEncode({'formatVersion': 2, 'activeTemplate': 'butterfly'}),
        );
        final original = await file.readAsString();
        expect(await RepositoryLocator().detect(store), isNull);
        await Directory('${root.path}/.git').create();
        final config = File('${root.path}/.git/config');
        await config.writeAsString(
          '[remote "upstream"]\nurl = https://github.com/other/repo\n[remote "origin"]\n url = git@github.com:alice/blog.git\n',
        );
        expect(
          (await RepositoryLocator().detect(store))!.fullName,
          'alice/blog',
        );
        expect(await file.readAsString(), original);
        await config.writeAsString(
          '[remote "origin"]\nurl = https://example.com/alice/blog\n',
        );
        expect(await RepositoryLocator().detect(store), isNull);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('lost local publication identity is restored only after explicit confirmation', () async {
    final root = await Directory.systemTemp.createTemp('binding-restore-');
    final auth = await authorized();
    final pages = ExistingPages(auth);
    final builder = FakeBuilder();
    final controller = PublishController(
      auth: auth,
      github: pages,
      builder: builder,
      browser: Browser(),
    );
    final file = File('${root.path}/blog.json');
    try {
      await file.writeAsString(
        jsonEncode({
          'formatVersion': 2,
          'activeTemplate': 'butterfly',
          'site': {'title': 'Local blog'},
        }),
      );
      final initial = await file.readAsString();
      await controller.open(
        ProjectSession(root: root.path),
        FileStore(PathGuard(root.path)),
      );
      final generatedId = controller.state!.workspaceId;
      await controller.selectRepository(PublishTarget('alice', 'blog'));
      expect(controller.repositoryToReconnect!.fullName, 'alice/blog');
      expect(controller.state!.workspaceId, generatedId);
      expect(await file.readAsString(), initial);
      expect(pages.uploads, 0);
      controller.cancelReconnection();
      expect(controller.repositoryToReconnect, isNull);
      expect(await file.readAsString(), initial);
      await controller.selectRepository(PublishTarget('alice', 'blog'));
      await controller.confirmReconnection();
      expect(controller.error, isEmpty);
      expect(controller.state!.workspaceId, pages.identity);
      expect(controller.state!.commit, 'remote-head');
      expect(controller.state!.url, Uri.parse('https://blog.example.com/'));
      expect(controller.repositoryToReconnect, isNull);
      expect(pages.uploads, 0);
      final persisted = jsonDecode(await file.readAsString());
      expect(persisted['publish'].containsKey('repositoryUrl'), false);
      expect(persisted['site']['title'], 'Local blog');
      await controller.open(
        ProjectSession(root: root.path),
        FileStore(PathGuard(root.path)),
      );
      expect(controller.state!.workspaceId, pages.identity);
    } finally {
      controller.dispose();
      builder.environment.dispose();
      await root.delete(recursive: true);
    }
  });

  test(
    'an unauthorized URL never offers recovery or modifies local configuration',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'binding-unauthorized-',
      );
      final auth = await authorized();
      final pages = ExistingPages(auth);
      final builder = FakeBuilder();
      final controller = PublishController(
        auth: auth,
        github: pages,
        builder: builder,
        browser: Browser(),
      );
      final file = File('${root.path}/blog.json');
      try {
        await file.writeAsString(
          jsonEncode({'formatVersion': 2, 'activeTemplate': 'butterfly'}),
        );
        final initial = await file.readAsString();
        await controller.open(
          ProjectSession(root: root.path),
          FileStore(PathGuard(root.path)),
        );
        await controller.selectRepository(PublishTarget('alice', 'other'));
        expect(controller.error, contains('尚未授权'));
        expect(controller.repositoryToReconnect, isNull);
        expect(await file.readAsString(), initial);
      } finally {
        controller.dispose();
        builder.environment.dispose();
        await root.delete(recursive: true);
      }
    },
  );
}
