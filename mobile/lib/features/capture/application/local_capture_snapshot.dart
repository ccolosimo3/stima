import 'package:flutter/foundation.dart';

import '../domain/local_capture.dart';

enum LocalRecordingPhase {
  idle,
  requestingPermission,
  starting,
  recording,
  finalizing,
}

enum LocalSaveState { loading, pending, saved, error }

enum LocalFailureKind { load, save, permission, recording, playback }

@immutable
class LocalCaptureFailure {
  const LocalCaptureFailure(this.kind, this.message, {this.clipId});
  final LocalFailureKind kind;
  final String message;
  final String? clipId;
}

@immutable
class LocalCaptureSnapshot {
  const LocalCaptureSnapshot({
    required this.capture,
    required this.notes,
    required this.recordingPhase,
    required this.saveState,
    required this.elapsed,
    required this.canRecord,
    required this.canRetry,
    required this.canEditNotes,
    required this.busy,
    this.playingClipId,
    this.failure,
  });

  final LocalCapture? capture;
  final String notes;
  final LocalRecordingPhase recordingPhase;
  final LocalSaveState saveState;
  final Duration elapsed;
  final bool canRecord;
  final bool canRetry;
  final bool canEditNotes;
  final bool busy;
  final String? playingClipId;
  final LocalCaptureFailure? failure;

  List<LocalAudioClip> get clips => capture?.clips ?? const [];
  bool canPlay(String id) =>
      !busy &&
      recordingPhase == LocalRecordingPhase.idle &&
      clips.any((clip) => clip.id == id && clip.state == LocalClipState.ready);
  bool canDelete(String id) =>
      !busy &&
      recordingPhase == LocalRecordingPhase.idle &&
      clips.any((clip) => clip.id == id);
}
