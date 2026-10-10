import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/models/publishing.dart';
import 'package:blog_studio/platform/contracts/desktop_platform.dart';
import 'package:blog_studio/services/publishing/blog_builder.dart';
import 'package:blog_studio/services/publishing/github_auth.dart';
import 'package:blog_studio/services/publishing/github_pages.dart';
import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/storage/publishing_store.dart';

class PublishController extends ChangeNotifier {
  PublishController({
    required this.auth,
    required this.builder,
    required this.browser,
    GitHubPages? github,
    this.onConfigurationChanged,
    this.pollInterval = const Duration(seconds: 10),
    this.deploymentTimeout = const Duration(minutes: 10),
  }) : github = github ?? GitHubPages(auth);
  final GitHubAuth auth;
  final BlogBuilder builder;
  final ExternalBrowser browser;
  final GitHubPages github;
  final Future<void> Function()? onConfigurationChanged;
  final Duration pollInterval, deploymentTimeout;
  ProjectSession? project;
  PublishingStore? _store;
  PublicationState? state;
  GitHubAccount? account;
  List<GitHubRepository> repositories = [];
  DeviceAuthorization? authorization;
  bool busy = false, publishing = false, _cancelled = false, _disposed = false;
  String message = '', error = '';
  bool get configured => auth.settings.configured;
  PublishTarget? get target => state?.target;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _check() {
    if (_cancelled || _disposed) throw PublishCancelled();
  }

  void _progress(String value) {
    message = value;
    _notify();
  }

  void _failure(Object e) {
    message = state?.pending == true ? '网页已上传，上线确认未完成。' : '操作未完成。';
    error = e is PublishingException ? e.message : '暂时无法完成操作，请检查网络或博客配置后重试。';
    _notify();
  }

  Future<void> _save(PublicationState value) async {
    // Retain the remote commit in memory even if disk persistence fails.
    state = value;
    await _store!.save(value);
    await onConfigurationChanged?.call();
  }

  Future<void> open(ProjectSession next, FileStore store) async {
    if (busy) return;
    busy = true;
    error = message = '';
    project = next;
    state = null;
    repositories = [];
    account = null;
    _store = PublishingStore(store);
    _notify();
    try {
      state = await _store!.load();
      account = await auth.restore();
      if (account != null) repositories = await github.repositories();
    } catch (e) {
      _failure(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> connect() async {
    if (busy) return;
    busy = true;
    _cancelled = false;
    error = '';
    _progress('正在连接 GitHub…');
    try {
      authorization = await auth.begin();
      _check();
      _notify();
      await browser.open(authorization!.verificationUri);
      account = await auth.complete(
        authorization!,
        cancelled: () => _cancelled || _disposed,
      );
      _check();
      repositories = await github.repositories();
      message = '账号已连接，请选择或授权发布仓库。';
    } on PublishCancelled {
      message = '连接已取消。';
    } catch (e) {
      _failure(e);
    } finally {
      authorization = null;
      busy = false;
      _notify();
    }
  }

  Future<void> disconnect() async {
    if (busy) return;
    busy = true;
    _notify();
    try {
      await auth.disconnect();
      account = null;
      repositories = [];
      message = '已断开本机账号连接。';
      error = '';
    } catch (e) {
      _failure(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> refreshRepositories() async {
    if (busy) return;
    busy = true;
    error = '';
    _notify();
    try {
      repositories = await github.repositories();
    } catch (e) {
      _failure(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> openInstallation() async {
    try {
      await browser.open(auth.settings.installationUri);
    } catch (e) {
      _failure(e);
    }
  }

  Future<void> createRepository() async {
    try {
      await browser.open(
        Uri.https('github.com', '/new', {
          'name': 'inkjian-blog',
          'description': 'My blog, published with InkJian',
          'visibility': 'public',
        }),
      );
    } catch (e) {
      _failure(e);
    }
  }

  Future<void> selectRepository(PublishTarget value) async {
    if (busy || state == null) return;
    busy = true;
    error = '';
    _progress('正在检查发布仓库…');
    try {
      final same = value.fullName == target?.fullName;
      await github.inspect(
        value,
        state!.workspaceId,
        expectedHead: same ? state!.commit : null,
      );
      if (!same) {
        await _save(
          PublicationState(workspaceId: state!.workspaceId, target: value),
        );
      }
      message = '发布仓库已关联。';
    } catch (e) {
      _failure(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> publish() async {
    if (busy || target == null || project == null || account == null) return;
    busy = publishing = true;
    _cancelled = false;
    error = '';
    WebsiteArtifact? artifact;
    _notify();
    try {
      final destination = target!;
      _progress('正在检查仓库安装授权…');
      repositories = await github.repositories();
      _check();
      if (!repositories.any(
        (r) =>
            r.target.fullName.toLowerCase() ==
            destination.fullName.toLowerCase(),
      )) {
        throw const PublishingException(
          '这个发布仓库尚未授权给 InkJian。请点击“授权仓库”，将它加入应用安装授权，再刷新仓库。',
        );
      }
      if (!state!.pending) {
        _progress('正在检查发布仓库…');
        final remote = await github.inspect(
          destination,
          state!.workspaceId,
          expectedHead: state!.commit,
        );
        _check();
        artifact = await builder.build(project!, progress: _progress);
        _check();
        // Check again after the build; changes made elsewhere must not be overwritten.
        _progress('网页构建完成，正在复查发布仓库…');
        final fresh = await github.inspect(
          destination,
          state!.workspaceId,
          expectedHead: remote.head,
        );
        _check();
        await artifact.verifyUnchanged();
        _check();
        final commit = await github.upload(
          destination,
          state!.workspaceId,
          fresh,
          artifact.files,
          progress: _progress,
          check: _check,
        );
        await _save(
          PublicationState(
            workspaceId: state!.workspaceId,
            target: destination,
            commit: commit,
            url: state!.url,
            publishedAt: state!.publishedAt,
            pending: true,
          ),
        );
      }
      _check();
      await github.inspect(
        destination,
        state!.workspaceId,
        expectedHead: state!.commit,
      );
      _check();
      _progress('网页已上传，正在等待 GitHub 上线…');
      final url = await github.enable(destination);
      _check();
      final deadline = DateTime.now().add(deploymentTimeout);
      while (true) {
        _check();
        if (await github.isBuilt(destination, state!.commit!)) {
          _check();
          await github.inspect(
            destination,
            state!.workspaceId,
            expectedHead: state!.commit,
          );
          await _save(
            PublicationState(
              workspaceId: state!.workspaceId,
              target: destination,
              commit: state!.commit,
              url: url,
              publishedAt: DateTime.now(),
            ),
          );
          message = '博客已上线。';
          break;
        }
        if (DateTime.now().isAfter(deadline)) {
          throw const PublishingException(
            '网页已上传，GitHub 仍在处理。稍后点击“继续确认上线”，无需重新上传。',
          );
        }
        await Future<void>.delayed(pollInterval);
      }
    } on PublishCancelled {
      message = state?.pending == true
          ? '网页已上传，上线确认已暂停。可稍后继续确认。'
          : '发布已取消，未更新网站。';
    } catch (e) {
      _failure(e);
    } finally {
      if (artifact != null) {
        try {
          await artifact.dispose();
        } catch (_) {
          /* Best-effort removal of temporary web output. */
        }
      }
      busy = publishing = false;
      _notify();
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    _progress(publishing ? '正在停止本机发布操作…' : '正在取消连接…');
    await builder.cancel();
  }

  Future<void> openWebsite() async {
    final url = state?.url;
    if (url == null || url.scheme != 'https') return;
    try {
      await browser.open(url);
    } catch (e) {
      _failure(e);
    }
  }

  @override
  void dispose() {
    _disposed = _cancelled = true;
    super.dispose();
  }
}
