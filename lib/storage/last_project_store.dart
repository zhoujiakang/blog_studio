import 'dart:convert';
import 'dart:io';

/// App-local navigation state, never a file inside the user's blog.
class LastProjectStore {
  LastProjectStore(this.file);
  final File file;
  Future<void> _writes = Future.value();

  Future<String?> read() async {
    try {
      if (!await file.exists() || await file.length() > 16384) return null;
      final value = jsonDecode(await file.readAsString());
      if (value is! Map || value['formatVersion'] != 1) return null;
      final root = value['lastProject'];
      return root is String && root.trim().isNotEmpty ? root : null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<void> remember(String? root) {
    final operation = _writes.then((_) async {
      await file.parent.create(recursive: true);
      final staging = await file.parent.createTemp('.session-');
      try {
        final temporary = File('${staging.path}/session.json');
        await temporary.writeAsString(
          jsonEncode({'formatVersion': 1, 'lastProject': root}),
          flush: true,
        );
        await temporary.rename(file.path);
      } finally {
        await staging.delete(recursive: true);
      }
    });
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }
}
