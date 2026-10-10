enum RuntimeStatus { ready, missing, incompatible, inaccessible }

class RuntimeEnvironment {
  const RuntimeEnvironment({
    required this.status,
    this.nodePath,
    this.npmPath,
    this.nodeVersion,
    this.npmVersion,
    this.reason,
  });
  final RuntimeStatus status;
  final String? nodePath, npmPath, nodeVersion, npmVersion, reason;
}
