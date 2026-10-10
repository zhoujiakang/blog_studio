enum StudioError {
  invalidProject,
  nonEmptyDirectory,
  permissionDenied,
  invalidMetadata,
  fileConflict,
  unsupportedImage,
  runtimeMissing,
  runtimeIncompatible,
  dependencyInstallFailed,
  dependencyManifestChanged,
  previewUnavailable,
}

class StudioException implements Exception {
  const StudioException(this.code, this.message);
  final StudioError code;
  final String message;
  @override
  String toString() => message;
}
