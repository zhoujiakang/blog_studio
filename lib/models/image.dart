import 'dart:typed_data';

class ImageInput {
  const ImageInput(this.bytes, {required this.name});
  final Uint8List bytes;
  final String name;
}

class ImportedImage {
  const ImportedImage({
    required this.relativeAssetPath,
    required this.markdownUrl,
    required this.mediaType,
    required this.byteLength,
    required this.imageId,
  });
  final String relativeAssetPath, markdownUrl, mediaType, imageId;
  final int byteLength;
}
