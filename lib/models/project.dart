class ProjectSession {
  const ProjectSession({required this.root});
  final String root;
}

enum DirectoryKind { empty, compatible, incompatible }

class DirectoryInspection {
  const DirectoryInspection(this.kind, {this.reason});
  final DirectoryKind kind;
  final String? reason;
}
