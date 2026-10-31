import 'package:flutter/foundation.dart';

const captureNotesMaxCodeUnits = 50000;
const captureMaxClips = 5;
const captureMaxClipDuration = Duration(seconds: 120);

enum LocalClipState { pending, ready, deleting }

@immutable
class LocalAudioClip {
  const LocalAudioClip({
    required this.id,
    required this.number,
    this.state = LocalClipState.pending,
    this.duration = Duration.zero,
  });

  final String id;
  final int number;
  final LocalClipState state;
  final Duration duration;

  // A filename is derived from validated identity, never supplied by metadata.
  String get fileName => '$id.m4a';

  LocalAudioClip withState(LocalClipState state, {Duration? duration}) =>
      LocalAudioClip(
        id: id,
        number: number,
        state: state,
        duration: duration ?? this.duration,
      );
}

@immutable
class LocalCapture {
  LocalCapture({
    required this.id,
    this.notes = '',
    this.nextClipNumber = 1,
    List<LocalAudioClip> clips = const [],
  }) : clips = List.unmodifiable(clips);

  final String id;
  final String notes;
  final int nextClipNumber;
  final List<LocalAudioClip> clips;

  LocalCapture copyWith({
    String? notes,
    int? nextClipNumber,
    List<LocalAudioClip>? clips,
  }) => LocalCapture(
    id: id,
    notes: notes ?? this.notes,
    nextClipNumber: nextClipNumber ?? this.nextClipNumber,
    clips: clips ?? this.clips,
  );
}
