/// Current article attributes. Unknown fields are preserved but not interpreted.
abstract final class ArticleMetadata {
  static List<String> values(dynamic value) {
    if (value == null) return const [];
    if (value is! List || value.any((item) => item is! String)) {
      throw const FormatException('标签和分类必须是字符串数组。');
    }
    return value.cast<String>().toList();
  }

  static void validate(Map<String, dynamic> fields) {
    for (final key in [
      'title',
      'date',
      'updated',
      'description',
      'cover',
      'slug',
    ]) {
      if (fields.containsKey(key) && fields[key] is! String) {
        throw FormatException('$key 必须是字符串。');
      }
    }
    for (final key in ['tags', 'categories']) {
      values(fields[key]);
    }
    for (final key in ['draft', 'published']) {
      if (fields.containsKey(key) && fields[key] is! bool) {
        throw FormatException('$key 必须是布尔值。');
      }
    }
  }
}
