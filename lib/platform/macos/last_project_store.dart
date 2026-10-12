import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:blog_studio/storage/last_project_store.dart';

class MacLastProjectStore extends LastProjectStore {
  MacLastProjectStore()
    : super(
        File(
          p.join(
            Platform.environment['HOME']!,
            'Library',
            'Application Support',
            'InkJian',
            'session.json',
          ),
        ),
      );
}
