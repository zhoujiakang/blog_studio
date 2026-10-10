import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/services/managed_runtime.dart';
import 'package:blog_studio/services/preview_manager.dart';
import 'package:blog_studio/services/runtime_detector.dart';
import 'package:blog_studio/models/project.dart';
import 'package:blog_studio/models/runtime_environment.dart';
import 'package:blog_studio/models/dependency_report.dart';
import 'package:blog_studio/ui/dialogs/preview_preparation_dialog.dart';

const ready = RuntimeEnvironment(
  status: RuntimeStatus.ready,
  nodePath: '/fake/node',
  npmPath: '/fake/npm',
  nodeVersion: 'v22.23.0',
);

class FakeManaged extends ManagedRuntime {
  FakeManaged() : super(directory: Directory('/unused'));
  int downloads = 0;
  RuntimeEnvironment? cached;
  Object? failure;
  @override
  Future<RuntimeEnvironment?> detect(
    ProjectSession project,
    RuntimeDetector detector,
  ) async => cached;
  @override
  Future<RuntimeEnvironment> install(
    ProjectSession project,
    RuntimeDetector detector,
    RuntimeProgress progress,
  ) async {
    downloads++;
    if (failure != null) throw failure!;
    progress('正在下载预览组件…', 0.5);
    cached = ready;
    return ready;
  }
}

class FakePreview extends PreviewManager {
  FakePreview(FakeManaged managed) : super(managedRuntime: managed);
  int installed = 0, started = 0;
  bool failInstall = false;
  bool failStart = false;
  Completer<void>? installGate;
  @override
  Future<DependencyReport> inspect(
    ProjectSession project,
    RuntimeEnvironment runtime,
  ) async => DependencyReport(
    status: installed > 0 ? DependencyStatus.ready : DependencyStatus.missing,
    manifestHash: 'fresh',
  );
  @override
  Future<void> install(
    ProjectSession project,
    RuntimeEnvironment runtime,
    DependencyReport approved,
  ) async {
    expect(approved.manifestHash, 'fresh');
    if (installGate != null) await installGate!.future;
    if (failInstall) throw StateError('npm TECHNICAL_ERROR');
    installed++;
  }

  @override
  Future<void> cancelInstall() async {
    if (installGate != null && !installGate!.isCompleted) {
      installGate!.complete();
    }
  }

  @override
  Future<Uri> start(ProjectSession project, RuntimeEnvironment runtime) async {
    started++;
    if (failStart) throw TimeoutException('local start');
    return Uri.parse('http://127.0.0.1:12345/');
  }
}

void main() {
  const project = ProjectSession(root: '/test-blog');
  test('single preparation downloads when needed; retry reuses runtime and takes a fresh dependency snapshot', () async {
    final managed = FakeManaged();
    final preview = FakePreview(managed);
    try {
      preview.failInstall = true;
      await expectLater(
        preview.prepareAndStart(
          project,
          const RuntimeEnvironment(status: RuntimeStatus.missing),
          null,
        ),
        throwsStateError,
      );
      expect(managed.downloads, 1);
      expect(preview.preparing, false);
      preview.failInstall = false;
      final url = await preview.prepareAndStart(
        project,
        const RuntimeEnvironment(status: RuntimeStatus.missing),
        const DependencyReport(
          status: DependencyStatus.missing,
          manifestHash: 'stale',
        ),
      );
      expect(url.host, '127.0.0.1');
      expect(managed.downloads, 1);
      expect(preview.installed, 1);
      await preview.prepareAndStart(project, ready, null);
      expect(preview.installed, 1);
      expect(preview.started, 2);
    } finally {
      preview.dispose();
    }
  });
  test(
    'download, dependencies and local startup report different failures',
    () async {
      final managed = FakeManaged()..failure = const SocketException('offline');
      final preview = FakePreview(managed);
      try {
        await expectLater(
          preview.prepareAndStart(
            project,
            const RuntimeEnvironment(status: RuntimeStatus.missing),
            null,
          ),
          throwsA(isA<SocketException>()),
        );
        expect(preview.preparationFailureMessage, contains('下载服务'));
        managed.failure = null;
        preview.failInstall = true;
        await expectLater(
          preview.prepareAndStart(project, ready, null),
          throwsStateError,
        );
        expect(preview.preparationFailureMessage, contains('博客依赖'));
        preview.failInstall = false;
        preview.failStart = true;
        await expectLater(
          preview.prepareAndStart(project, ready, null),
          throwsA(isA<TimeoutException>()),
        );
        expect(preview.preparationFailureMessage, contains('启动超时'));
        expect(preview.preparationFailureMessage, isNot(contains('下载')));
      } finally {
        preview.dispose();
      }
    },
  );
  test('cancelling preparation never starts the preview', () async {
    final preview = FakePreview(FakeManaged())..installGate = Completer<void>();
    final future = preview.prepareAndStart(project, ready, null);
    await Future<void>.delayed(Duration.zero);
    final assertion = expectLater(
      future,
      throwsA(isA<PreviewPreparationCancelled>()),
    );
    await preview.cancelPreparation();
    await assertion;
    expect(preview.started, 0);
    expect(preview.preparing, false);
    preview.dispose();
  });
  testWidgets(
    'ordinary users see progress and retry without commands, paths or raw logs',
    (tester) async {
      final preview = FakePreview(FakeManaged());
      var attempts = 0;
      final gate = Completer<Uri>();
      Uri? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<Uri>(
                  context: context,
                  builder: (_) => PreviewPreparationDialog(
                    preview: preview,
                    start: () {
                      attempts++;
                      return attempts == 1
                          ? Future.error(
                              StateError(
                                'npm TECHNICAL_ERROR /opt/homebrew/node',
                              ),
                            )
                          : gate.future;
                    },
                  ),
                );
              },
              child: const Text('浏览博客'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('浏览博客'));
      await tester.pumpAndSettle();
      expect(find.text('暂时无法打开预览'), findsOneWidget);
      expect(find.textContaining('TECHNICAL_ERROR'), findsNothing);
      expect(find.textContaining('Node'), findsNothing);
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      gate.complete(Uri.parse('http://127.0.0.1:12345/'));
      await tester.pumpAndSettle();
      expect(result!.host, '127.0.0.1');
      expect(find.byType(AlertDialog), findsNothing);
      preview.dispose();
    },
  );
}
