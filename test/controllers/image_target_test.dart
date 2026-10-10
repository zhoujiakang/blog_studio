import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/app/app_dependencies.dart';
import 'package:blog_studio/controllers/studio_controller.dart';
import 'package:blog_studio/models/image.dart';
import 'package:blog_studio/platform/contracts/desktop_platform.dart';
import 'package:blog_studio/services/editor_session.dart';
import 'package:blog_studio/storage/article_repository.dart';

import 'studio_controller_test.dart' show TestEditor, TestPrompts, TestPreview;

class WaitingClipboard implements ClipboardImages {
  final result = Completer<ImageInput?>();
  @override
  Future<ImageInput?> readImage() => result.future;
  @override
  Future<void> writeText(String text) async {}
}

class WaitingFiles implements FileDialogs {
  final result = Completer<ImageInput?>();
  @override
  Future<String?> chooseBlogDirectory() async => null;
  @override
  Future<ImageInput?> chooseImage({String label = '图片'}) => result.future;
}

class RecordingImages extends EditorSession {
  RecordingImages() : super(editor: TestEditor());
  final inserted = <String>[];
  @override
  Future<void> insertImage(ImageInput input) async =>
      inserted.add(article!.relativePath);
  @override
  Future<void> setCover(ImageInput input) async =>
      inserted.add(article!.relativePath);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final operation in ['paste', 'pick', 'cover']) {
    for (final destination in ['other', 'reopen', 'same']) {
      test('$operation respects document identity: $destination', () async {
        final root = await Directory.systemTemp.createTemp(
          'inkjian-image-target-',
        );
        final session = RecordingImages();
        session.repository = ArticleRepository(root.path);
        await session.createArticle('A');
        final first = session.article!.relativePath;
        final second = await session.repository!.create('B');
        final clipboard = WaitingClipboard();
        final files = WaitingFiles();
        final base = AppDependencies.macos;
        final prompts = TestPrompts();
        final preview = TestPreview();
        final deps = AppDependencies(
          files: files,
          clipboard: clipboard,
          window: base.window,
          browser: base.browser,
          runtime: base.runtime,
          processes: base.processes,
          createEditorHost: base.createEditorHost,
        );
        final controller = StudioController(
          session: session,
          preview: preview,
          prompts: prompts,
          dependencies: deps,
        );
        try {
          final task = switch (operation) {
            'paste' => controller.pasteImage(),
            'cover' => controller.pickCover(),
            _ => controller.pickImage(),
          };
          if (destination != 'same') {
            expect(
              await session.openArticle(
                destination == 'other' ? second.relativePath : first,
              ),
              true,
            );
          }
          final image = ImageInput(Uint8List.fromList([1]), name: 'image.png');
          (operation == 'paste' ? clipboard.result : files.result).complete(
            image,
          );
          await task;
          expect(session.inserted, destination == 'same' ? [first] : isEmpty);
          expect(
            prompts.messages,
            destination == 'same' ? isEmpty : ['文章已切换，请在当前文章重新插图。'],
          );
        } finally {
          controller.dispose();
          preview.dispose();
          session.dispose();
          await root.delete(recursive: true);
        }
      });
    }
  }
}
