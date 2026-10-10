import 'dart:convert';

/// Rejects delayed events from an old document and non-monotonic revisions.
class WebEditorProtocol {
  String session = '';
  int revision = 0;
  bool composing = false;
  String markdown = '';

  void open(String id, String source) {
    session = id;
    markdown = source;
    revision = 0;
    composing = false;
  }

  Map<String, dynamic>? accept(String raw) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic> || decoded['protocol'] != 1) {
      return null;
    }
    if (decoded['type'] == 'ready') return decoded;
    if (decoded['session'] != session) return null;
    if (decoded['type'] == 'composition') {
      composing = decoded['composing'] == true;
    }
    if (decoded['type'] == 'change') {
      final next = decoded['revision'];
      if (next is! int || next <= revision || decoded['markdown'] is! String) {
        return null;
      }
      revision = next;
      markdown = decoded['markdown'] as String;
      composing = decoded['composing'] == true;
    }
    return decoded;
  }
}
