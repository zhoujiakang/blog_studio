import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'package:blog_studio/models/dependency_report.dart';
import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/models/runtime_environment.dart';
import 'package:blog_studio/services/dependency_manager.dart';
import 'package:blog_studio/services/runtime_detector.dart';
import 'package:blog_studio/services/managed_runtime.dart';

class PreviewManager extends ChangeNotifier {
  PreviewManager({
    RuntimeDetector? runtimeDetector,
    ManagedRuntime? managedRuntime,
  }) : runtimeDetector = runtimeDetector ?? RuntimeDetector(),
       managedRuntime = managedRuntime ?? ManagedRuntime();
  final RuntimeDetector runtimeDetector;
  final ManagedRuntime managedRuntime;
  bool preparing = false, _cancelPreparation = false;
  String preparationMessage = '正在检查预览…';
  String? preparationFailureMessage;
  double? preparationProgress;
  void _progress(String message, [double? fraction]) {
    preparationMessage = message;
    preparationProgress = fraction;
    _notify();
  }

  void _checkPreparation() {
    if (_cancelPreparation) throw PreviewPreparationCancelled();
  }

  Future<RuntimeEnvironment> detectRuntime(ProjectSession project) async {
    final system = await runtimeDetector.detect(project);
    if (system.status == RuntimeStatus.ready) return system;
    return await managedRuntime.detect(project, runtimeDetector) ?? system;
  }

  Future<void> cancelPreparation() async {
    if (!preparing) return;
    _cancelPreparation = true;
    _progress('正在取消…');
    managedRuntime.cancel();
    await cancelInstall();
    await stop();
  }

  Future<Uri> prepareAndStart(
    ProjectSession project,
    RuntimeEnvironment runtime,
    DependencyReport? report,
  ) => _prepareOperation(project, runtime, report, '预览', (ready) async {
    _progress('正在打开本地博客…');
    final result = await start(project, ready);
    if (_cancelPreparation) {
      await stop();
      throw PreviewPreparationCancelled();
    }
    return result;
  });

  /// Reuses preview preparation without starting a local web server.
  Future<RuntimeEnvironment> prepareForBuild(
    ProjectSession project, {
    bool Function()? cancelled,
  }) async {
    final runtime = await detectRuntime(project);
    if (cancelled?.call() == true) throw PreviewPreparationCancelled();
    return _prepareOperation(
      project,
      runtime,
      null,
      '发布',
      (ready) async => ready,
    );
  }

  Future<T> _prepareOperation<T>(
    ProjectSession project,
    RuntimeEnvironment runtime,
    DependencyReport? report,
    String purpose,
    Future<T> Function(RuntimeEnvironment) finish,
  ) async {
    if (preparing) throw StateError('已有环境准备正在进行');
    preparing = true;
    _cancelPreparation = false;
    error = null;
    preparationFailureMessage = null;
    var stage = 'runtime';
    _progress('正在检查$purpose所需组件…');
    try {
      if (runtime.status != RuntimeStatus.ready) {
        final cached = await managedRuntime.detect(project, runtimeDetector);
        _checkPreparation();
        runtime =
            cached ??
            await managedRuntime.install(project, runtimeDetector, (
              message,
              fraction,
            ) {
              if (!_cancelPreparation) _progress(message, fraction);
            });
      }
      _checkPreparation();
      stage = 'dependencies';
      _progress('正在检查博客依赖…');
      report = await inspect(project, runtime);
      _checkPreparation();
      if (report.status != DependencyStatus.ready) {
        _progress('正在准备博客，首次使用可能需要几分钟…');
        await install(project, runtime, report);
      }
      _checkPreparation();
      stage = 'start';
      return await finish(runtime);
    } catch (e) {
      if (_cancelPreparation) throw PreviewPreparationCancelled();
      error = '$e';
      preparationFailureMessage = switch (stage) {
        'runtime' =>
          e is SocketException || e is HttpException || e is TimeoutException
              ? '暂时无法连接预览组件下载服务。请稍后重试，文章和图片不会受影响。'
              : '预览组件准备失败，请重新尝试。文章和图片会保留。',
        'dependencies' => '博客依赖准备失败，请重新尝试。文章和图片会保留。',
        _ => e is TimeoutException ? '本地博客启动超时，请重新尝试。' : '本地博客未能启动，请重新尝试。',
      };
      rethrow;
    } finally {
      preparing = false;
      _notify();
    }
  }

  Directory? _resources;
  Process? _server, _installer;
  final _requests = <int, Completer<Map<String, dynamic>>>{};
  int _request = 0;
  Uri? url;
  String? root;
  bool installing = false;
  String log = '';
  String? error;
  bool _disposed = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _log(String value) {
    log += value;
    if (log.length > 24000) log = log.substring(log.length - 24000);
    _notify();
  }

  Future<Directory> scripts() async {
    if (_resources != null) return _resources!;
    final dir = await Directory.systemTemp.createTemp('studio-preview-tools-');
    for (final name in [
      'layout.mjs',
      'probe.mjs',
      'server.mjs',
      'install.mjs',
      'build.mjs',
      'platform/index.mjs',
      'platform/macos.mjs',
    ]) {
      final file = File(p.join(dir.path, name));
      await file.parent.create(recursive: true);
      await file.writeAsString(
        await rootBundle.loadString('integrations/preview/$name'),
      );
    }
    return _resources = Directory(await dir.resolveSymbolicLinks());
  }

  Future<DependencyReport> inspect(
    ProjectSession project,
    RuntimeEnvironment runtime,
  ) async {
    return DependencyManager(
      probePath: p.join((await scripts()).path, 'probe.mjs'),
      runtimeDetector: runtimeDetector,
    ).inspect(project, runtime);
  }

  Future<void> install(
    ProjectSession project,
    RuntimeEnvironment runtime,
    DependencyReport approved,
  ) async {
    if (installing) throw StateError('已有安装正在进行');
    installing = true;
    log = '';
    error = null;
    _notify();
    final done = Completer<void>();
    try {
      final process = await runtimeDetector.processes.start(
        runtime.nodePath!,
        [
          p.join((await scripts()).path, 'install.mjs'),
          project.root,
          runtime.npmPath!,
          jsonEncode({
            'manifestHash': approved.manifestHash,
            'lockHash': approved.lockHash,
          }),
        ],
        environment: runtimeDetector.subprocessEnvironment(runtime.nodePath!),
        includeParentEnvironment: false,
      );
      _installer = process;
      if (preparing && _cancelPreparation) process.stdin.writeln('cancel');
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              try {
                final event = jsonDecode(line) as Map;
                if (event['type'] == 'log') _log(event['text'] as String);
                if (event['type'] == 'done' && !done.isCompleted) {
                  done.complete();
                }
                if (event['type'] == 'error' && !done.isCompleted) {
                  done.completeError(StateError(event['message'] as String));
                }
              } catch (e) {
                if (!done.isCompleted) done.completeError(e);
              }
            },
            onError: (Object e) {
              if (!done.isCompleted) done.completeError(e);
            },
          );
      process.stderr.transform(utf8.decoder).listen(_log);
      unawaited(
        process.exitCode.then((code) {
          if (!done.isCompleted) {
            done.completeError(StateError('安装进程退出（$code）'));
          }
        }),
      );
      await done.future;
      await process.exitCode;
      final health = await inspect(project, runtime);
      if (health.status != DependencyStatus.ready) {
        throw StateError(health.reason ?? '安装后的依赖检查失败');
      }
    } catch (e) {
      error = '$e';
      rethrow;
    } finally {
      _installer = null;
      installing = false;
      _notify();
    }
  }

  Future<void> cancelInstall() async {
    final process = _installer;
    if (process == null) return;
    process.stdin.writeln('cancel');
    await process.stdin.flush();
    // The Node supervisor terminates its own npm process group and cleans staging.
    await process.exitCode.timeout(const Duration(seconds: 15));
  }

  Future<Uri> start(ProjectSession project, RuntimeEnvironment runtime) async {
    if (root == project.root && url != null) {
      await refresh();
      return url!;
    }
    await stop();
    error = null;
    final process = await runtimeDetector.processes.start(
      runtime.nodePath!,
      [
        p.join((await scripts()).path, 'server.mjs'),
        project.root,
        runtime.npmPath!,
      ],
      environment: runtimeDetector.subprocessEnvironment(runtime.nodePath!),
      includeParentEnvironment: false,
    );
    _server = process;
    if (preparing && _cancelPreparation) {
      await stop();
      throw PreviewPreparationCancelled();
    }
    root = project.root;
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          try {
            final event = jsonDecode(line) as Map<String, dynamic>;
            final pending = _requests[event['request']];
            if (event['type'] == 'log') {
              _log(event['text'] as String? ?? '');
            } else if (event['type'] == 'error') {
              error = event['message'] as String?;
              for (final c in _requests.values) {
                if (!c.isCompleted) {
                  c.completeError(StateError(error ?? '预览失败'));
                }
              }
            } else if (pending != null && !pending.isCompleted) {
              pending.complete(event);
            }
          } catch (e) {
            error = '预览协议错误：$e';
          }
          _notify();
        });
    process.stderr.transform(utf8.decoder).listen(_log);
    unawaited(
      process.exitCode.then((code) {
        if (_server == process) {
          _server = null;
          url = null;
          root = null;
          error = '预览已停止（$code）';
          for (final c in _requests.values) {
            if (!c.isCompleted) c.completeError(StateError(error!));
          }
          _notify();
        }
      }),
    );
    try {
      final event = await _send('start');
      final ready = Uri.parse(event['url'] as String);
      if (ready.scheme != 'http' ||
          ready.host != '127.0.0.1' ||
          ready.port <= 0) {
        throw StateError('预览返回了非本机地址');
      }
      url = ready;
      _notify();
      return ready;
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _send(String type) async {
    final id = ++_request;
    final c = Completer<Map<String, dynamic>>();
    _requests[id] = c;
    try {
      _server!.stdin.writeln(jsonEncode({'type': type, 'request': id}));
      return await c.future.timeout(
        Duration(seconds: type == 'start' ? 45 : 30),
      );
    } finally {
      _requests.remove(id);
    }
  }

  Future<void> refresh() async {
    if (_server != null && url != null) await _send('refresh');
  }

  Future<void> stop() async {
    final process = _server;
    if (process == null) return;
    _server = null;
    url = null;
    root = null;
    for (final request in _requests.values) {
      if (!request.isCompleted) request.completeError(StateError('预览已停止'));
    }
    try {
      process.stdin.writeln(
        jsonEncode({'type': 'stop', 'request': ++_request}),
      );
      await process.stdin.close();
      await process.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      runtimeDetector.processes.terminate(process, force: true);
    }
    _notify();
  }

  Future<void> shutdown() async {
    managedRuntime.cancel();
    await cancelInstall();
    await stop();
    if (_resources != null) {
      await _resources!.delete(recursive: true);
      _resources = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
