import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';

/// Native boundary only. The controller owns intent, membership and retry.
abstract interface class LocalCaptureAudio {
  Future<bool> requestPermission();
  Future<void> start(String path, {required void Function() onInterruption});
  Future<void> stop();
  Future<Duration> inspect(String path);
  Future<void> play(
    String path, {
    required void Function() onComplete,
    required void Function() onError,
  });
  Future<void> stopPlayback();
  Future<void> close();
}

class NativeLocalCaptureAudio implements LocalCaptureAudio {
  AudioRecorder? _recorder;
  StreamSubscription<RecordState>? _recordEvents;
  AudioPlayer? _player;
  StreamSubscription<AudioEvent>? _playEvents;
  bool _stopping = false;

  @override
  Future<bool> requestPermission() async {
    _recorder ??= AudioRecorder();
    return _recorder!.hasPermission();
  }

  @override
  Future<void> start(
    String path, {
    required void Function() onInterruption,
  }) async {
    final recorder = _recorder ??= AudioRecorder();
    _stopping = false;
    _recordEvents = recorder.onStateChanged().listen(
      (state) {
        if (!_stopping && state != RecordState.record) onInterruption();
      },
      onError: (Object error, StackTrace stack) {
        if (!_stopping) onInterruption();
      },
    );
    await recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 16000,
        numChannels: 1,
        audioInterruption: AudioInterruptionMode.pause,
      ),
      path: path,
    );
  }

  @override
  Future<void> stop() async {
    _stopping = true;
    final recorder = _recorder;
    if (recorder == null) return;
    try {
      // Null may mean native system teardown already stopped it. The caller
      // retains the reserved path and validates that file independently.
      await recorder.stop();
    } finally {
      await _recordEvents?.cancel();
      _recordEvents = null;
      _recorder = null;
      await recorder.dispose();
    }
  }

  @override
  Future<Duration> inspect(String path) async {
    final player = AudioPlayer();
    try {
      await player.setSource(DeviceFileSource(path));
      final duration = await player.getDuration();
      if (duration == null || duration <= Duration.zero) {
        throw StateError('Audio has no playable duration.');
      }
      return duration;
    } finally {
      await player.dispose();
    }
  }

  @override
  Future<void> play(
    String path, {
    required void Function() onComplete,
    required void Function() onError,
  }) async {
    await stopPlayback();
    final player = _player = AudioPlayer();
    // Native errors can arrive after play() has acknowledged preparation.
    _playEvents = player.eventStream.listen((event) {
      if (event.eventType == AudioEventType.complete) onComplete();
    }, onError: (Object error, StackTrace stack) => onError());
    await player.play(DeviceFileSource(path));
  }

  @override
  Future<void> stopPlayback() async {
    await _playEvents?.cancel();
    _playEvents = null;
    final player = _player;
    _player = null;
    if (player != null) {
      try {
        await player.stop();
      } finally {
        await player.dispose();
      }
    }
  }

  @override
  Future<void> close() async {
    await stopPlayback();
    await stop();
  }
}
