class BlogTemplate {
  const BlogTemplate({
    required this.id,
    required this.name,
    required this.files,
  });
  final String id;
  final String name;
  final List<Map<String, dynamic>> files;
}
