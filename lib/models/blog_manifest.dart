import 'dart:convert';

/// Shared blog format validation; it has no filesystem or service dependency.
abstract final class BlogManifest {
  static bool validTemplateId(String id) =>
      RegExp(r'^[a-zA-Z0-9\u4e00-\u9fff][a-zA-Z0-9_\u4e00-\u9fff-]*$')
          .hasMatch(id);

  static Map<String, dynamic> decode(List<int> bytes) {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map ||
        value['formatVersion'] != 2 ||
        value['activeTemplate'] is! String ||
        !validTemplateId(value['activeTemplate'])) {
      throw const FormatException('博客资源格式或模板名称不支持。');
    }
    return Map<String, dynamic>.from(value);
  }
}
