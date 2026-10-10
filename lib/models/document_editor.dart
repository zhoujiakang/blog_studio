import 'package:flutter/foundation.dart';
import 'package:blog_studio/models/image.dart';

/// Document operations consumed by workspace business logic. Host binding and
/// JavaScript evaluation belong to the concrete editor/controller, not this port.
abstract class DocumentEditor extends ChangeNotifier {
  String get documentId;
  String get markdown;
  bool get composing;
  String? get error;
  VoidCallback? get onSave;
  set onSave(VoidCallback? callback);
  VoidCallback? get onPasteImage;
  set onPasteImage(VoidCallback? callback);
  Future<void> open(String source, {Map<String, String> images = const {}});
  Future<void> bookmarkImageSelection();
  Future<void> insertImage(ImportedImage image, Uint8List bytes);
  Future<void> insertMarkdown(
    String markdown, {
    Map<String, String> images = const {},
  });
  Future<String> serialize();
  Future<void> command(String type);
  Future<void> releaseKeyboard();
}
