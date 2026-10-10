import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:blog_studio/models/image.dart';
import 'package:blog_studio/models/studio_exception.dart';
import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/storage/image_importer.dart';
import 'package:blog_studio/storage/path_guard.dart';

Future<Uint8List> tinyPng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff000000), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(1, 1);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'oversized declared input is rejected before subscribing to data',
    () async {
      var read = false;
      Stream<List<int>> input() async* {
        read = true;
        yield [1];
      }

      await expectLater(
        ImageImporter.readBytes(input(), length: ImageImporter.maxBytes + 1),
        throwsA(isA<StudioException>()),
      );
      expect(read, false);
    },
  );
  test('stream growth cannot bypass the byte limit', () async {
    Stream<List<int>> input() async* {
      yield Uint8List(ImageImporter.maxBytes);
      yield [1];
      fail('reader must cancel oversized stream');
    }

    await expectLater(
      ImageImporter.readBytes(input(), length: 1),
      throwsA(isA<StudioException>()),
    );
  });
  test(
    'large sparse file is rejected and valid image imports unchanged',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inkjian-image-limit-',
      );
      try {
        final file = File('${root.path}/large.png');
        final handle = await file.open(mode: FileMode.write);
        await handle.truncate(ImageImporter.maxBytes + 1);
        await handle.close();
        await expectLater(
          ImageImporter.readFile(file.path),
          throwsA(isA<StudioException>()),
        );
        final png = await tinyPng();
        final small = File('${root.path}/small.png');
        await small.writeAsBytes(png);
        final input = await ImageImporter.readFile(small.path);
        expect(input.bytes, png);
        final result = await ImageImporter(FileStore(PathGuard(root.path)))
            .import(input);
        expect(
          await File('${root.path}/${result.relativeAssetPath}').readAsBytes(),
          png,
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'pixel limit is checked from image header before full frame decoding',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inkjian-image-pixels-',
      );
      try {
        final png = await tinyPng();
        final data = ByteData.sublistView(png);
        data.setUint32(16, 8192);
        data.setUint32(20, 8192);
        var crc = 0xffffffff;
        for (final byte in png.sublist(12, 29)) {
          crc ^= byte;
          for (var bit = 0; bit < 8; bit++) {
            crc = (crc & 1) != 0 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
          }
        }
        data.setUint32(29, (crc ^ 0xffffffff) & 0xffffffff);
        await expectLater(
          ImageImporter(FileStore(PathGuard(root.path)))
              .import(ImageInput(png, name: 'huge.png')),
          throwsA(
            isA<StudioException>().having(
              (e) => e.message,
              'reason',
              contains('尺寸'),
            ),
          ),
        );
        expect(await Directory('${root.path}/resource/images').exists(), false);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
