import 'dart:async';
import 'dart:typed_data';

import 'package:super_clipboard/super_clipboard.dart';

import 'package:blog_studio/models/image.dart';
import 'package:blog_studio/storage/image_importer.dart';

Future<ImageInput?> readClipboardImage() async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return null;
  final reader = await clipboard.read();
  if (!reader.canProvide(Formats.png)) return null;
  final completer = Completer<Uint8List?>();
  final progress = reader.getFile(Formats.png, (file) async {
    try {
      completer.complete(await ImageImporter.readBytes(file.getStream()));
    } catch (e) {
      completer.completeError(e);
    }
  }, onError: completer.completeError);
  if (progress == null) return null;
  final bytes = await completer.future.timeout(const Duration(seconds: 10));
  return bytes == null ? null : ImageInput(bytes, name: 'clipboard.png');
}
