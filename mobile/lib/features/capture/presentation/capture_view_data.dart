import 'package:flutter/foundation.dart';

enum CaptureRecordingPhase { idle, starting, recording, finalizing }

enum CaptureNoticeTone { information, warning, error }

@immutable
class CaptureClip {
  const CaptureClip({
    required this.id,
    required this.number,
    required this.duration,
    this.status,
    this.canPlay = false,
    this.canDelete = true,
    this.playing = false,
  });

  final String id;
  final int number;
  final Duration duration;
  final String? status;
  final bool canPlay;
  final bool canDelete;
  final bool playing;
}

@immutable
class CaptureNotice {
  const CaptureNotice(
    this.message, {
    this.tone = CaptureNoticeTone.information,
  });

  final String message;
  final CaptureNoticeTone tone;
}

/// Supplied display data only; recording, persistence and jobs belong to callers.
@immutable
class CaptureViewData {
  CaptureViewData({
    required this.notes,
    List<CaptureClip> clips = const [],
    List<CaptureClip> pendingClips = const [],
    this.recordingPhase = CaptureRecordingPhase.idle,
    this.elapsed = Duration.zero,
    this.inputLocked = false,
    this.canRecord = true,
    this.canExtract = false,
    this.canStartBlank = true,
    this.canDeleteClips = true,
    this.canStopRecording = true,
    this.notice,
    this.microphoneNotice,
  }) : clips = List.unmodifiable(clips),
       pendingClips = List.unmodifiable(pendingClips);

  final String notes;
  final List<CaptureClip> clips;
  final List<CaptureClip> pendingClips;
  final CaptureRecordingPhase recordingPhase;
  final Duration elapsed;
  final bool inputLocked;
  final bool canRecord;
  final bool canExtract;
  final bool canStartBlank;
  final bool canDeleteClips;
  final bool canStopRecording;
  final CaptureNotice? notice;
  final CaptureNotice? microphoneNotice;
}

String captureDuration(Duration duration) {
  final minutes = duration.inMinutes.toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
