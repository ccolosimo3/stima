import 'dart:async';
import 'dart:io';

import 'package:stima_mobile/features/capture/data/local_capture_audio.dart';

/// Widget tests cross the real controller/store; this seam cannot prove codecs.
class LocalCaptureTestAudio implements LocalCaptureAudio {
  Completer<void>? stopGate;
  bool failPlay = false;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> start(
    String path, {
    required void Function() onInterruption,
  }) async {
    await File(path).writeAsBytes([1, 2, 3, 4], flush: true);
  }

  @override
  Future<void> stop() async {
    if (stopGate case final gate?) await gate.future;
  }

  @override
  Future<Duration> inspect(String path) async => const Duration(seconds: 4);

  @override
  Future<void> play(
    String path, {
    required void Function() onComplete,
    required void Function() onError,
  }) async {
    if (failPlay) throw StateError('Test playback failed');
    if (!await File(path).exists()) throw StateError('Test file missing');
  }

  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> close() async {}
}
