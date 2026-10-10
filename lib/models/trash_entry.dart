class TrashEntry {
  const TrashEntry({
    required this.id,
    required this.originalPath,
    required this.deletedAt,
    required this.contentHash,
    required this.title,
  });
  final String id, originalPath, contentHash, title;
  final DateTime deletedAt;
}

class TrashListing {
  const TrashListing(this.entries, {this.errors = const {}});
  final List<TrashEntry> entries;
  final Map<String, String> errors;
}
