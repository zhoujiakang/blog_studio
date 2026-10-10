import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;

import 'package:blog_studio/models/image.dart';
import 'package:blog_studio/models/studio_exception.dart';
import 'package:blog_studio/storage/file_store.dart';
import 'package:blog_studio/storage/resource_layout.dart';

class ImageImporter {
  static const maxBytes = 40 * 1024 * 1024;
  static const maxPixels = 32 * 1000 * 1000;
  static const maxDimension = 16384;

  static void _checkSize(int length) {
    if (length > maxBytes) {
      throw const StudioException(
        StudioError.unsupportedImage,
        '图片大小不能超过 40 MB。',
      );
    }
  }

  /// Check declared size before reading, and enforce the limit as data arrives.
  static Future<Uint8List> readBytes(
    Stream<List<int>> stream, {
    int? length,
  }) async {
    if (length != null) _checkSize(length);
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      _checkSize(bytes.length + chunk.length);
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  static Future<ImageInput> readFile(String path) async {
    final file = File(path);
    final length = await file.length();
    _checkSize(length);
    return ImageInput(
      await readBytes(file.openRead(), length: length),
      name: p.basename(path),
    );
  }

  ImageImporter(this.store);
  final FileStore store;
  static String? mediaType(List<int> bytes) {
    bool starts(List<int> signature) =>
        bytes.length >= signature.length &&
        List.generate(
          signature.length,
          (i) => bytes[i] == signature[i],
        ).every((b) => b);
    if (starts([137, 80, 78, 71, 13, 10, 26, 10])) return 'image/png';
    if (starts([255, 216, 255])) return 'image/jpeg';
    if (starts([71, 73, 70, 56])) return 'image/gif';
    if (starts([82, 73, 70, 70]) &&
        bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    return null;
  }

  Future<ImportedImage> import(ImageInput input) async {
    final type = mediaType(input.bytes);
    if (type == null || input.bytes.length > maxBytes) {
      throw const StudioException(
        StudioError.unsupportedImage,
        '请选择 PNG、JPEG、GIF 或 WebP 图片，大小不超过 40 MB。',
      );
    }
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(input.bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width > maxDimension ||
          descriptor.height > maxDimension ||
          descriptor.width * descriptor.height > maxPixels) {
        throw const StudioException(
          StudioError.unsupportedImage,
          '图片尺寸过大，请缩小到 3200 万像素以内，单边不超过 16384 像素。',
        );
      }
      codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } on StudioException {
      rethrow;
    } catch (_) {
      throw const StudioException(
        StudioError.unsupportedImage,
        '图片损坏或无法解码，未插入正文。',
      );
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
    final extension = {
      'image/png': 'png',
      'image/jpeg': 'jpg',
      'image/gif': 'gif',
      'image/webp': 'webp',
    }[type]!;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final relative =
        '${ResourceLayout(store.guard.root).images}/studio-$id.$extension';
    await store.write(relative, input.bytes, expectedHash: null);
    return ImportedImage(
      relativeAssetPath: relative,
      markdownUrl: '/img/studio-$id.$extension',
      mediaType: type,
      byteLength: input.bytes.length,
      imageId: id,
    );
  }

  Future<Map<String, String>> resolveImages(String source) async {
    final images = <String, String>{};
    final urls = RegExp(r'/img/[\w/.-]+')
        .allMatches(source)
        .map((m) => m.group(0)!)
        .toSet();
    for (final url in urls) {
      try {
        final bytes = await store.read(
          ResourceLayout(store.guard.root).imagePath(url),
        );
        final type = mediaType(bytes);
        if (type != null) {
          images[url] = 'data:$type;base64,${base64Encode(bytes)}';
        }
      } catch (_) {
        /* Missing or unsafe images remain placeholders. */
      }
    }
    return images;
  }
}
