enum SaveStatus { clean, dirty, saving, failed, conflict }

class SaveState {
  const SaveState({
    this.status = SaveStatus.clean,
    this.currentRevision = 0,
    this.savedRevision = 0,
    this.error,
  });
  final SaveStatus status;
  final int currentRevision, savedRevision;
  final String? error;
}

class FlushResult {
  const FlushResult(this.success, {this.error});
  final bool success;
  final Object? error;
}
