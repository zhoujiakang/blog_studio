import 'dart:convert';
import 'dart:io';

import 'package:blog_studio/controllers/publish_controller.dart';
import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/storage/path_guard.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/models/publishing.dart';
import 'package:blog_studio/services/publishing/github_pages.dart';

import 'publishing_test.dart'
    show StubTransport, authorized, FakePages, FakeBuilder, Browser;

class ReconnectingPages extends FakePages {
  ReconnectingPages(super.auth);
  String? expected;
  bool fail = false;
  @override
  Future<RemoteWebsite> reconnect(
    PublishTarget target,
    String workspaceId, {
    String? expectedHead,
  }) async {
    expected = expectedHead;
    if (fail) throw const PublishingException('网页内容已变化');
    return const RemoteWebsite('domain-head', {}, cname: 'blog.example.com');
  }
}

void main() {
  test('reselecting the same repository updates baseline and keeps publication state', () async {
    final root = await Directory.systemTemp.createTemp('publishing-reconnect-');
    final auth = await authorized();
    final pages = ReconnectingPages(auth);
    final builder = FakeBuilder();
    final controller = PublishController(
      auth: auth,
      builder: builder,
      browser: Browser(),
      github: pages,
    );
    try {
      await File('${root.path}/blog.json').writeAsString(
        jsonEncode({
          'formatVersion': 2,
          'activeTemplate': 'butterfly',
          'publish': {
            'provider': 'github-pages',
            'owner': 'Alice',
            'repository': 'Blog',
            'workspaceId': 'workspace',
            'commit': 'old',
            'url': 'https://alice.github.io/blog/',
            'publishedAt': '2026-10-10T00:00:00.000Z',
            'pending': true,
          },
        }),
      );
      await controller.open(
        ProjectSession(root: root.path),
        FileStore(PathGuard(root.path)),
      );
      final publishedAt = controller.state!.publishedAt;
      await controller.selectRepository(PublishTarget('alice', 'blog'));
      expect(controller.error, isEmpty);
      expect(pages.expected, 'old');
      expect(controller.state!.commit, 'domain-head');
      expect(controller.state!.publishedAt, publishedAt);
      expect(controller.state!.pending, true);
      expect(controller.state!.url, Uri.parse('https://blog.example.com/'));
      final saved = await File('${root.path}/blog.json').readAsString();
      expect(jsonDecode(saved)['publish']['commit'], 'domain-head');
      pages.fail = true;
      await controller.selectRepository(PublishTarget('alice', 'blog'));
      expect(controller.error, contains('网页内容已变化'));
      expect(await File('${root.path}/blog.json').readAsString(), saved);
    } finally {
      controller.dispose();
      builder.environment.dispose();
      await root.delete(recursive: true);
    }
  });
  final target = PublishTarget('alice', 'blog');
  for (final scenario in [
    'add',
    'change',
    'remove',
    'html',
    'other-blog',
    'invalid',
  ]) {
    test(
      'reconnect validates ownership and permits only domain edits: $scenario',
      () async {
        final marker = utf8.encode(
          jsonEncode({
            'formatVersion': 1,
            'workspaceId': scenario == 'other-blog' ? 'another' : 'workspace',
            'files': ['index.html'],
          }),
        );
        final cname = utf8.encode(
          scenario == 'invalid'
              ? 'https://blog.example.com/\n'
              : 'blog.example.com\n',
        );
        final cnameSha = GitHubPages.blobHash(cname);
        final calls = <String>[];
        final transport = StubTransport((method, uri, body) async {
          calls.add(method);
          if (uri.path == '/user') return {'login': 'alice'};
          if (uri.path.endsWith('/git/ref/heads/main')) {
            return {
              'object': {'sha': 'new'},
            };
          }
          if (uri.path.contains('/git/commits/')) {
            return {
              'tree': {'sha': uri.path.split('/').last},
            };
          }
          if (uri.path.contains('/git/trees/')) {
            final old = uri.path.endsWith('/old');
            final files = {
              '.inkjian-site.json': 'marker',
              'index.html': scenario == 'html' && !old ? 'changed' : 'html',
              if (old && ['change', 'remove'].contains(scenario))
                'CNAME': 'previous-domain',
              if (!old && scenario != 'remove') 'CNAME': cnameSha,
            };
            return {
              'tree': [
                for (final e in files.entries)
                  {
                    'path': e.key,
                    'sha': e.value,
                    'type': 'blob',
                    'mode': '100644',
                  },
              ],
            };
          }
          if (uri.path.contains('/git/blobs/')) {
            return {
              'encoding': 'base64',
              'content': base64Encode(
                uri.path.endsWith('/marker') ? marker : cname,
              ),
            };
          }
          return {
            'owner': {'login': 'alice'},
            'name': 'blog',
            'permissions': {'admin': true},
            'default_branch': 'main',
            'size': 1,
          };
        });
        final pages = GitHubPages(await authorized(transport: transport));
        if (['html', 'other-blog', 'invalid'].contains(scenario)) {
          await expectLater(
            pages.reconnect(target, 'workspace', expectedHead: 'old'),
            throwsA(isA<PublishingException>()),
          );
        } else {
          final remote = await pages.reconnect(
            target,
            'workspace',
            expectedHead: 'old',
          );
          expect(remote.head, 'new');
          expect(
            remote.cname,
            scenario == 'remove' ? null : 'blog.example.com',
          );
          // An ordinary publish still rejects a changed head until reconnected.
          await expectLater(
            pages.inspect(target, 'workspace', expectedHead: 'old'),
            throwsA(isA<PublishingException>()),
          );
        }
        expect(calls.every((method) => method == 'GET'), true);
      },
    );
  }

  test(
    'upload preserves custom domain and declares it in the managed files',
    () async {
      Map? tree;
      Map? marker;
      final domain = utf8.encode('blog.example.com\n');
      final transport = StubTransport((method, uri, body) async {
        if (uri.path == '/user') return {'login': 'alice'};
        if (uri.path.endsWith('/git/blobs')) {
          final bytes = base64Decode((body as Map)['content']);
          final value = utf8.decode(bytes);
          if (value.startsWith('{')) marker = jsonDecode(value) as Map;
          return {'sha': GitHubPages.blobHash(bytes)};
        }
        if (uri.path.endsWith('/git/trees')) {
          tree = body as Map;
          return {'sha': 'tree'};
        }
        if (uri.path.endsWith('/git/commits')) {
          expect((body as Map)['parents'], ['new']);
          return {'sha': 'published'};
        }
        expect(method, 'PATCH');
        expect((body as Map)['force'], false);
        return {};
      });
      final pages = GitHubPages(await authorized(transport: transport));
      await pages.upload(
        target,
        'workspace',
        RemoteWebsite('new', {
          'CNAME': GitHubPages.blobHash(domain),
        }, cname: 'blog.example.com'),
        {'index.html': utf8.encode('site')},
        progress: (_) {},
        check: () {},
      );
      expect(marker!['files'], contains('CNAME'));
      expect(
        (tree!['tree'] as List).singleWhere((e) => e['path'] == 'CNAME')['sha'],
        GitHubPages.blobHash(domain),
      );
    },
  );

  test(
    'Pages can return HTTP while custom-domain certificate is pending',
    () async {
      final pages = GitHubPages(
        await authorized(
          transport: StubTransport((method, uri, body) async {
            if (uri.path == '/user') return {'login': 'alice'};
            return {
              'build_type': 'legacy',
              'source': {'branch': 'main', 'path': '/'},
              'cname': 'blog.example.com',
              'html_url': 'http://blog.example.com/',
            };
          }),
        ),
      );
      expect(await pages.enable(target), Uri.parse('http://blog.example.com/'));
    },
  );
}
