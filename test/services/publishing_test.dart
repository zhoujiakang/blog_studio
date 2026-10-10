import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/controllers/publish_controller.dart';
import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/models/publishing.dart';
import 'package:blog_studio/platform/contracts/credential_store.dart';
import 'package:blog_studio/platform/contracts/desktop_platform.dart';
import 'package:blog_studio/services/preview_manager.dart';
import 'package:blog_studio/services/publishing/blog_builder.dart';
import 'package:blog_studio/services/publishing/github_auth.dart';
import 'package:blog_studio/services/publishing/github_pages.dart';
import 'package:blog_studio/services/publishing/github_transport.dart';
import 'package:blog_studio/services/publishing/public_images.dart';
import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/storage/path_guard.dart';

class MemoryCredentials implements CredentialStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

class StubTransport implements GitHubTransport {
  StubTransport(this.handle);
  final Future<dynamic> Function(String, Uri, Object?) handle;
  @override
  Future<dynamic> request(
    String method,
    Uri uri, {
    String? token,
    Object? body,
  }) => handle(method, uri, body);
}

class Browser implements ExternalBrowser {
  @override
  Future<void> open(Uri uri) async {}
}

class FakeBuilder extends BlogBuilder {
  FakeBuilder() : super(PreviewManager());
  int builds = 0;
  Directory? output;
  @override
  Future<WebsiteArtifact> build(
    ProjectSession project, {
    required void Function(String) progress,
  }) async {
    builds++;
    output = await Directory.systemTemp.createTemp('publish-test-output-');
    return WebsiteArtifact(output!, {
      'index.html': utf8.encode('<h1>public</h1>'),
    });
  }
}

class FakePages extends GitHubPages {
  FakePages(super.auth);
  bool built = false, conflict = false;
  int uploads = 0;
  bool authorizedRepository = true;
  @override
  Future<List<GitHubRepository>> repositories() async => authorizedRepository
      ? [
          GitHubRepository.fromJson({
            'owner': {'login': 'alice'},
            'name': 'blog',
            'permissions': {'admin': true},
          }),
        ]
      : [];
  @override
  Future<RemoteWebsite> inspect(
    PublishTarget target,
    String workspaceId, {
    String? expectedHead,
  }) async {
    if (conflict) throw const PublishingException('远程变化');
    return const RemoteWebsite(null, {});
  }

  @override
  Future<String> upload(
    PublishTarget target,
    String workspaceId,
    RemoteWebsite remote,
    Map<String, List<int>> input, {
    required void Function(String) progress,
    required void Function() check,
  }) async {
    check();
    uploads++;
    return 'commit-123';
  }

  @override
  Future<Uri> enable(PublishTarget target) async => target.website;
  @override
  Future<bool> isBuilt(PublishTarget target, String commit) async => built;
}

Future<GitHubAuth> authorized({GitHubTransport? transport}) async {
  final store = MemoryCredentials()
    ..value = const GitHubCredentials('TEST_SECRET', null).encode();
  final auth = GitHubAuth(
    store: store,
    transport:
        transport ??
        StubTransport((method, uri, body) async => {'login': 'alice'}),
  );
  await auth.restore();
  return auth;
}

void main() {
  test('only installed app repositories are offered, never public readable repositories', () async {
    final calls = <String>[];
    final transport = StubTransport((method, uri, body) async {
      calls.add(uri.path);
      if (uri.path == '/user') return {'login': 'alice'};
      if (uri.path == '/user/installations') {
        return {
          'installations': [
            {
              'id': 9,
              'app_slug': 'inkjian-publisher',
              'account': {'login': 'alice'},
              'permissions': {
                'contents': 'write',
                'pages': 'write',
                'administration': 'write',
              },
            },
            {
              'id': 10,
              'app_slug': 'other-app',
              'account': {'login': 'alice'},
            },
          ],
        };
      }
      if (uri.path == '/user/installations/9/repositories') {
        return {
          'repositories': [
            {
              'owner': {'login': 'alice'},
              'name': 'authorized-blog',
              'permissions': {'admin': true},
            },
            {
              'owner': {'login': 'alice'},
              'name': 'private-blog',
              'private': true,
              'permissions': {'admin': true},
            },
          ],
        };
      }
      throw StateError('Unexpected request: $uri');
    });
    final pages = GitHubPages(await authorized(transport: transport));
    expect((await pages.repositories()).map((r) => r.target.fullName), [
      'alice/authorized-blog',
    ]);
    expect(calls, isNot(contains('/user/repos')));
  });

  test(
    'pending installation permissions are reported before listing repositories',
    () async {
      final transport = StubTransport((method, uri, body) async {
        if (uri.path == '/user') return {'login': 'alice'};
        return {
          'installations': [
            {
              'id': 9,
              'app_slug': 'inkjian-publisher',
              'account': {'login': 'alice'},
              'permissions': {
                'contents': 'read',
                'pages': 'write',
                'administration': 'write',
              },
            },
          ],
        };
      });
      final pages = GitHubPages(await authorized(transport: transport));
      await expectLater(
        pages.repositories(),
        throwsA(
          isA<PublishingException>().having(
            (e) => e.message,
            'message',
            contains('contents'),
          ),
        ),
      );
    },
  );

  test('403 diagnostics identify failed operation and endpoint requirements without exposing body', () {
    final failure = GitHubFailure.response(
      403,
      'PUT',
      Uri.https(
        'api.github.com',
        '/repos/alice/blog/contents/.inkjian-site.json',
      ),
      reason: 'Resource not accessible by integration',
      requiredPermissions: 'contents=write',
    );
    expect(failure.message, contains('初始化发布仓库失败'));
    expect(failure.message, contains('contents=write'));
    final limited = GitHubFailure.response(
      403,
      'POST',
      Uri.https('api.github.com', '/repos/alice/blog/pages'),
      rateLimited: true,
    );
    expect(limited.message, contains('请求额度'));
    final unknown = GitHubFailure.response(
      403,
      'POST',
      Uri.https('api.github.com', '/repos/alice/blog/pages'),
      reason: 'TEST_SECRET',
    );
    expect(unknown.message, isNot(contains('TEST_SECRET')));
    expect(unknown.message, contains('开启 GitHub Pages失败'));
  });

  test('official builds have the InkJian GitHub App configured by default', () {
    const settings = GitHubAppSettings();
    expect(settings.configured, true);
    expect(settings.clientId, 'Iv23liMycMnHN9ykBFne');
    expect(settings.slug, 'inkjian-publisher');
    expect(
      settings.installationUri.toString(),
      'https://github.com/apps/inkjian-publisher/installations/new',
    );
  });

  test(
    'device flow obeys slow_down, stores token only in credential adapter',
    () async {
      final store = MemoryCredentials();
      var attempt = 0;
      final waits = <Duration>[];
      final auth = GitHubAuth(
        store: store,
        settings: const GitHubAppSettings(
          clientId: 'client',
          slug: 'inkjian-test',
        ),
        transport: StubTransport((method, uri, body) async {
          expect((body as Map?)?.containsKey('client_secret') ?? false, false);
          if (uri.path == '/login/device/code') {
            return {
              'device_code': 'device',
              'user_code': 'CODE-1234',
              'expires_in': 100,
              'interval': 5,
            };
          }
          if (uri.path == '/user') return {'login': 'alice'};
          attempt++;
          return switch (attempt) {
            1 => {'error': 'slow_down'},
            2 => {'error': 'authorization_pending'},
            _ => {'access_token': 'secret-token', 'expires_in': 28800},
          };
        }),
      );
      final device = await auth.begin();
      final account = await auth.complete(
        device,
        cancelled: () => false,
        wait: (duration) async {
          waits.add(duration);
        },
      );
      expect(account.login, 'alice');
      expect(waits.map((d) => d.inSeconds), [5, 10, 10]);
      expect(GitHubCredentials.decode(store.value!).token, 'secret-token');
      await auth.disconnect();
      expect(store.value, isNull);
    },
  );
  test(
    'cancelled and expired authorization never writes a credential',
    () async {
      final store = MemoryCredentials();
      final auth = GitHubAuth(store: store);
      final device = DeviceAuthorization(
        code: 'device',
        userCode: 'CODE',
        expiresAt: DateTime.now().add(const Duration(minutes: 1)),
        interval: Duration.zero,
      );
      await expectLater(
        auth.complete(device, cancelled: () => true),
        throwsA(isA<PublishCancelled>()),
      );
      expect(store.value, isNull);
      store.value = GitHubCredentials(
        'expired',
        DateTime.now().subtract(const Duration(hours: 1)),
      ).encode();
      expect(await auth.restore(), isNull);
      expect(store.value, isNull);
    },
  );
  test('non-empty unrelated repositories and externally changed heads are rejected', () async {
    var external = false;
    final transport = StubTransport((method, uri, body) async {
      if (uri.path == '/user') return {'login': 'alice'};
      if (uri.path.endsWith('/git/ref/heads/main')) {
        return {
          'object': {'sha': external ? 'changed' : 'head'},
        };
      }
      if (uri.path.endsWith('/git/commits/head')) {
        return {
          'tree': {'sha': 'tree'},
        };
      }
      if (uri.path.contains('/git/trees/')) {
        return {
          'tree': [
            {
              'path': 'important.txt',
              'type': 'blob',
              'mode': '100644',
              'sha': 'file',
            },
          ],
        };
      }
      return {
        'owner': {'login': 'alice'},
        'name': 'blog',
        'private': false,
        'permissions': {'admin': true},
        'default_branch': 'main',
        'size': 1,
      };
    });
    final pages = GitHubPages(await authorized(transport: transport));
    await expectLater(
      pages.inspect(PublishTarget('alice', 'blog'), 'workspace'),
      throwsA(isA<PublishingException>()),
    );
    external = true;
    await expectLater(
      pages.inspect(
        PublishTarget('alice', 'blog'),
        'workspace',
        expectedHead: 'head',
      ),
      throwsA(isA<PublishingException>()),
    );
  });
  test('upload deduplicates blobs, makes one commit, deletes stale files and never force pushes', () async {
    final calls = <String>[];
    Map? tree;
    final input = {'index.html': utf8.encode('new html')};
    final transport = StubTransport((method, uri, body) async {
      calls.add('$method ${uri.path}');
      if (uri.path == '/user') return {'login': 'alice'};
      if (uri.path.endsWith('/git/blobs')) {
        return {
          'sha': GitHubPages.blobHash(base64Decode((body as Map)['content'])),
        };
      }
      if (uri.path.endsWith('/git/trees')) {
        tree = body as Map;
        return {'sha': 'tree'};
      }
      if (uri.path.endsWith('/git/commits')) {
        expect((body as Map)['parents'], ['old-head']);
        return {'sha': 'new-head'};
      }
      expect(method, 'PATCH');
      expect((body as Map)['force'], false);
      return {};
    });
    final pages = GitHubPages(await authorized(transport: transport));
    final head = await pages.upload(
      PublishTarget('alice', 'blog'),
      'workspace',
      RemoteWebsite('old-head', {
        'index.html': GitHubPages.blobHash(input['index.html']!),
        'stale.js': 'stale',
      }),
      input,
      progress: (_) {},
      check: () {},
    );
    expect(head, 'new-head');
    expect(tree!.containsKey('base_tree'), false);
    expect(
      (tree!['tree'] as List).map((e) => e['path']),
      containsAll(['index.html', '.nojekyll', '.inkjian-site.json']),
    );
    expect((tree!['tree'] as List).any((e) => e['path'] == 'stale.js'), false);
    expect(calls.where((c) => c.endsWith('/git/blobs')).length, 2);
    expect(calls.where((c) => c.endsWith('/git/commits')).length, 1);
  });
  test('uploaded commit stays pending until that exact commit is deployed; retry does not build again', () async {
    final root = await Directory.systemTemp.createTemp('publishing-blog-');
    final builder = FakeBuilder();
    final auth = await authorized();
    final pages = FakePages(auth);
    final controller = PublishController(
      auth: auth,
      builder: builder,
      browser: Browser(),
      github: pages,
      deploymentTimeout: Duration.zero,
      pollInterval: Duration.zero,
    );
    try {
      await File('${root.path}/blog.json').writeAsString(
        jsonEncode({
          'formatVersion': 2,
          'activeTemplate': 'butterfly',
          'site': {'title': 'keep'},
        }),
      );
      await controller.open(
        ProjectSession(root: root.path),
        FileStore(PathGuard(root.path)),
      );
      await controller.selectRepository(PublishTarget('alice', 'blog'));
      pages.authorizedRepository = false;
      await controller.publish();
      expect(controller.error, contains('尚未授权'));
      expect(controller.message, '操作未完成。');
      expect(builder.builds, 0);
      expect(pages.uploads, 0);
      pages.authorizedRepository = true;
      await controller.publish();
      expect(controller.state!.pending, true);
      expect(controller.state!.publishedAt, isNull);
      expect(controller.error, contains('仍在处理'));
      expect(builder.builds, 1);
      expect(await builder.output!.exists(), false);
      final marker = jsonDecode(
        await File('${root.path}/blog.json').readAsString(),
      );
      expect(marker['site']['title'], 'keep');
      expect(jsonEncode(marker), isNot(contains('TEST_SECRET')));
      pages.built = true;
      await controller.publish();
      expect(controller.state!.pending, false);
      expect(controller.state!.publishedAt, isNotNull);
      expect(controller.message, '博客已上线。');
      expect(builder.builds, 1);
      expect(pages.uploads, 1);
    } finally {
      controller.dispose();
      builder.environment.dispose();
      await root.delete(recursive: true);
    }
  });
  test('empty repository is bootstrapped before using Git Data APIs', () async {
    var seeded = false;
    final calls = <String>[];
    final transport = StubTransport((method, uri, body) async {
      calls.add('$method ${uri.path}');
      if (uri.path == '/user') return {'login': 'alice'};
      if (uri.path.endsWith('/contents/.inkjian-site.json')) {
        expect(method, 'PUT');
        seeded = true;
        return {
          'commit': {'sha': 'seed'},
        };
      }
      if (uri.path.endsWith('/git/ref/heads/main')) {
        return {
          'object': {'sha': 'seed'},
        };
      }
      if (uri.path.endsWith('/git/commits/seed')) {
        return {
          'tree': {'sha': 'seed-tree'},
        };
      }
      if (uri.path.endsWith('/git/trees/seed-tree')) {
        return {
          'tree': [
            {
              'path': '.inkjian-site.json',
              'mode': '100644',
              'type': 'blob',
              'sha': 'seed-blob',
            },
          ],
        };
      }
      if (uri.path.endsWith('/git/blobs/seed-blob')) {
        return {
          'encoding': 'base64',
          'content': base64Encode(
            utf8.encode(
              jsonEncode({
                'formatVersion': 1,
                'workspaceId': 'workspace',
                'files': [],
              }),
            ),
          ),
        };
      }
      if (uri.path.endsWith('/git/blobs')) {
        expect(seeded, true);
        return {
          'sha': GitHubPages.blobHash(base64Decode((body as Map)['content'])),
        };
      }
      if (uri.path.endsWith('/git/trees')) return {'sha': 'tree'};
      if (uri.path.endsWith('/git/commits')) {
        expect((body as Map)['parents'], ['seed']);
        return {'sha': 'published'};
      }
      if (method == 'PATCH') {
        expect((body as Map)['force'], false);
        return {};
      }
      return {
        'owner': {'login': 'alice'},
        'name': 'blog',
        'private': false,
        'permissions': {'admin': true},
        'default_branch': 'main',
        'size': 1,
      };
    });
    final pages = GitHubPages(await authorized(transport: transport));
    expect(
      await pages.upload(
        PublishTarget('alice', 'blog'),
        'workspace',
        const RemoteWebsite(null, {}),
        {'index.html': utf8.encode('site')},
        progress: (_) {},
        check: () {},
      ),
      'published',
    );
    expect(
      calls.any((c) => c.startsWith('POST') && c.endsWith('/git/refs')),
      false,
    );
  });
  test(
    'Pages success for a different commit is not reported as our success',
    () async {
      final transport = StubTransport(
        (method, uri, body) async => uri.path == '/user'
            ? {'login': 'alice'}
            : [
                {'commit': 'someone-else', 'status': 'built'},
                {'commit': 'ours', 'status': 'building'},
              ],
      );
      final pages = GitHubPages(await authorized(transport: transport));
      expect(
        await pages.isBuilt(PublishTarget('alice', 'blog'), 'ours'),
        false,
      );
    },
  );
  test(
    'output rejects private folders and symbolic links before upload',
    () async {
      final root = await Directory.systemTemp.createTemp('publishing-output-');
      try {
        await File('${root.path}/index.html').writeAsString('html');
        await Directory('${root.path}/resource').create();
        await File('${root.path}/resource/secret.txt').writeAsString('PRIVATE');
        await expectLater(
          BlogBuilder.collect(root),
          throwsA(isA<PublishingException>()),
        );
        await Directory('${root.path}/resource').delete(recursive: true);
        await Link('${root.path}/outside.html').create('/etc/passwd');
        await expectLater(
          BlogBuilder.collect(root),
          throwsA(isA<PublishingException>()),
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
  test('public image selection excludes drafts, notes, private metadata and backup files', () async {
    final root = await Directory.systemTemp.createTemp('publishing-images-');
    try {
      for (final dir in [
        'resource/posts',
        'resource/drafts',
        'resource/notes',
        'template/butterfly',
      ]) {
        await Directory('${root.path}/$dir').create(recursive: true);
      }
      await File('${root.path}/blog.json').writeAsString(
        jsonEncode({
          'formatVersion': 2,
          'activeTemplate': 'butterfly',
          'site': {'avatar': '/img/background.svg'},
        }),
      );
      await File('${root.path}/template/butterfly/template.json').writeAsString(
        jsonEncode({
          'fields': [
            {'type': 'image', 'value': '/img/avatar.png'},
          ],
        }),
      );
      await File('${root.path}/resource/posts/public.md').writeAsString(
        '---\ncover: /img/cover.png\ncustom: /img/private-meta.png\n---\n![image](/img/public.png)',
      );
      await File('${root.path}/resource/posts/uppercase.MD')
          .writeAsString('![](/img/uppercase.png)');
      await File('${root.path}/resource/posts/hidden.md')
          .writeAsString('---\npublished: false\n---\n![](/img/hidden.png)');
      await File('${root.path}/resource/posts/a.md.studio.tmp')
          .writeAsString('![](/img/backup.png)');
      await File('${root.path}/resource/drafts/private.md')
          .writeAsString('![](/img/draft.png)');
      await File('${root.path}/resource/notes/private.md')
          .writeAsString('![](/img/note.png)');
      await File('${root.path}/resource/about.md')
          .writeAsString('![](/img/about.png)');
      expect(await PublicImages.referenced(root.path), {
        'public.png',
        'uppercase.png',
        'cover.png',
        'background.svg',
        'avatar.png',
        'about.png',
      });
    } finally {
      await root.delete(recursive: true);
    }
  });
}
