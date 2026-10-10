enum DependencyStatus { ready, missing, broken, manifestMismatch }

class DependencyReport {
  const DependencyReport({
    required this.status,
    required this.manifestHash,
    this.lockHash,
    this.missing = const [],
    this.reason,
  });
  final DependencyStatus status;
  final String manifestHash;
  final String? lockHash, reason;
  final List<String> missing;
}
