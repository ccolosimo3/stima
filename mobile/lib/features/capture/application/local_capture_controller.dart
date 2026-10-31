import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:uuid/uuid.dart';

import '../data/local_capture_audio.dart';
import '../data/local_capture_store.dart';
import '../domain/local_capture.dart';
import 'local_capture_snapshot.dart';

class _SaveFailure implements Exception {}

/// Owns one local Capture. Commands serialize file/native effects, while intent
/// and accepted text change synchronously so late acknowledgements cannot win.
/// Native bytes are never discarded by interruption or failed publication.
class LocalCaptureController extends ChangeNotifier {
  LocalCaptureController({
    required this._store,
    required this._audio,
    this.notesDebounce = const Duration(milliseconds: 350),
    this.recordingLimit = captureMaxClipDuration,
  }) {
    if (recordingLimit <= Duration.zero ||
        recordingLimit > captureMaxClipDuration) {
      throw ArgumentError.value(recordingLimit, 'recordingLimit');
    }
  }

  final LocalCaptureStore _store;
  final LocalCaptureAudio _audio;
  final Duration notesDebounce;
  final Duration recordingLimit;
  LocalCapture? _capture;
  String _notes = '';
  bool _dirty = false;
  bool _loading = true;
  bool _closing = false;
  bool _closed = false;
  int _busy = 0;
  int _intent = 0;
  String? _activeClipId;
  String? _playingClipId;
  int _playIntent = 0;
  LocalRecordingPhase _phase = LocalRecordingPhase.idle;
  LocalCaptureFailure? _failure;
  AppLifecycleState _lifecycle = AppLifecycleState.detached;
  Completer<void>? _resume;
  Timer? _notesTimer;
  Timer? _recordTimer;
  Timer? _limitTimer;
  final Stopwatch _elapsed = Stopwatch();
  Future<void> _tail = Future.value();

  LocalCaptureSnapshot get snapshot => LocalCaptureSnapshot(
    capture: _capture,
    notes: _notes,
    recordingPhase: _phase,
    saveState: _loading
        ? LocalSaveState.loading
        : _failure?.kind == LocalFailureKind.load ||
              _failure?.kind == LocalFailureKind.save
        ? LocalSaveState.error
        : _dirty
        ? LocalSaveState.pending
        : LocalSaveState.saved,
    elapsed: _elapsed.elapsed,
    canRecord:
        !_closing &&
        !_loading &&
        _capture != null &&
        _busy == 0 &&
        _phase == LocalRecordingPhase.idle &&
        _lifecycle == AppLifecycleState.resumed &&
        _capture!.clips.length < captureMaxClips &&
        !_capture!.clips.any((clip) => clip.state != LocalClipState.ready),
    canRetry:
        !_closing &&
        _busy == 0 &&
        (_failure?.kind == LocalFailureKind.load ||
            _dirty ||
            (_capture?.clips.any(
                  (clip) => clip.state != LocalClipState.ready,
                ) ??
                false)),
    canEditNotes: !_closing && !_loading && _capture != null,
    busy: _busy > 0 || _closing,
    playingClipId: _playingClipId,
    failure: _failure,
  );

  void _changed() {
    if (!_closed) notifyListeners();
  }

  Future<void> _run(
    Future<void> Function() operation,
    LocalFailureKind kind,
    String message, {
    bool allowClosing = false,
  }) {
    if (_closed || (_closing && !allowClosing)) return Future.value();
    _busy++;
    final result = _tail.then((_) async {
      try {
        await operation();
      } catch (error) {
        _failure = LocalCaptureFailure(
          error is _SaveFailure ? LocalFailureKind.save : kind,
          error is _SaveFailure
              ? 'Your latest changes are not saved yet. Existing notes and audio are kept; retry saving.'
              : message,
          clipId: _activeClipId,
        );
      } finally {
        _busy--;
        _changed();
      }
    });
    _tail = result;
    _changed();
    return result;
  }

  Future<void> initialize() => _run(
    () async {
      if (_capture != null) return;
      _loading = true;
      try {
        _capture = await _store.load();
        _notes = _capture!.notes;
        _dirty = false;
        _failure = null;
      } finally {
        _loading = false;
      }
      await _recover();
    },
    LocalFailureKind.load,
    'Your saved Capture could not be opened. Nothing has been replaced. Retry opening it.',
  );

  void updateNotes(String committedNotes) {
    if (!snapshot.canEditNotes ||
        committedNotes.length > captureNotesMaxCodeUnits ||
        committedNotes == _notes) {
      return;
    }
    _notes = committedNotes;
    _dirty = true;
    if (_failure?.kind == LocalFailureKind.save) _failure = null;
    _notesTimer?.cancel();
    _notesTimer = Timer(notesDebounce, () => unawaited(flush()));
    _changed();
  }

  // Merge current accepted notes at execution time. A newer edit during the
  // write stays dirty; it never receives the previous generation's saved label.
  Future<void> _publish(LocalCapture next) async {
    final committed = next.copyWith(notes: _notes);
    try {
      await _store.save(committed);
    } catch (_) {
      _dirty = true;
      throw _SaveFailure();
    }
    _capture = committed;
    _dirty = _notes != committed.notes;
    if (_failure?.kind == LocalFailureKind.save) _failure = null;
    _changed();
  }

  Future<void> _flush() async {
    _notesTimer?.cancel();
    if (_capture != null && _dirty) await _publish(_capture!);
  }

  Future<void> flush() => _run(
    _flush,
    LocalFailureKind.save,
    'Your latest changes are not saved yet. They are still here; retry saving.',
  );

  Future<void> startRecording() {
    if (!snapshot.canRecord) return Future.value();
    final intent = ++_intent;
    _phase = LocalRecordingPhase.requestingPermission;
    _failure = null;
    return _run(
      () async {
        try {
          await _stopPlayback();
          await _flush();
          if (intent != _intent ||
              _closing ||
              _lifecycle != AppLifecycleState.resumed) {
            return;
          }
          final allowed = await _audio.requestPermission();
          if (intent != _intent || _closing) return;
          if (!allowed) {
            _failure = const LocalCaptureFailure(
              LocalFailureKind.permission,
              'Microphone access is off. You can keep typing notes. Allow microphone access in device settings to record.',
            );
            return;
          }
          if (_lifecycle == AppLifecycleState.inactive) {
            _resume = Completer<void>();
            await _resume!.future;
            _resume = null;
          }
          if (intent != _intent ||
              _closing ||
              _lifecycle != AppLifecycleState.resumed) {
            return;
          }
          final capture = _capture!;
          final clip = LocalAudioClip(
            id: const Uuid().v4(),
            number: capture.nextClipNumber,
          );
          await _publish(
            capture.copyWith(
              clips: [...capture.clips, clip],
              nextClipNumber: clip.number + 1,
            ),
          );
          if (intent != _intent ||
              _closing ||
              _lifecycle != AppLifecycleState.resumed) {
            // Reservation precedes microphone access. No bytes exist in this path.
            await _publish(
              _capture!.copyWith(
                clips: _capture!.clips.where((c) => c.id != clip.id).toList(),
              ),
            );
            return;
          }
          final file = await _store.audioFile(_capture!, clip);
          if (await file.exists()) {
            throw StateError('Recording destination already exists.');
          }
          if (intent != _intent ||
              _closing ||
              _lifecycle != AppLifecycleState.resumed) {
            await _publish(
              _capture!.copyWith(
                clips: _capture!.clips
                    .where((value) => value.id != clip.id)
                    .toList(),
              ),
            );
            return;
          }
          _activeClipId = clip.id;
          _phase = LocalRecordingPhase.starting;
          _changed();
          await _audio.start(
            file.path,
            onInterruption: () => _interrupt(clip.id),
          );
          if (intent != _intent ||
              _closing ||
              _lifecycle != AppLifecycleState.resumed) {
            await _finalize();
            return;
          }
          _phase = LocalRecordingPhase.recording;
          _elapsed
            ..reset()
            ..start();
          _recordTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
            _changed();
          });
          _limitTimer = Timer(recordingLimit, () => unawaited(stopRecording()));
        } finally {
          if (_phase == LocalRecordingPhase.requestingPermission ||
              (_phase == LocalRecordingPhase.starting &&
                  _activeClipId == null)) {
            _phase = LocalRecordingPhase.idle;
          }
        }
      },
      LocalFailureKind.recording,
      'Recording could not finish. Available audio has been kept. Retry saving it, or delete the unfinished clip.',
    ).then((_) async {
      // A thrown Start can still have created bytes. Stop and inspect them via
      // the ordinary finalization path, without destructive native cancel.
      if (_activeClipId != null && _phase == LocalRecordingPhase.starting) {
        await stopRecording();
      }
    });
  }

  void _interrupt(String clipId) {
    if (_activeClipId != clipId || _phase == LocalRecordingPhase.finalizing) {
      return;
    }
    unawaited(stopRecording());
  }

  void _cancelIntent() {
    _intent++;
    if (_resume case final value? when !value.isCompleted) value.complete();
  }

  Future<void> stopRecording() {
    _cancelIntent();
    return _run(
      () async {
        await _finalize();
        await _flush();
      },
      LocalFailureKind.recording,
      'Audio could not be saved as a playable clip. Available bytes are kept. Retry, or delete the unfinished clip.',
    );
  }

  Future<void> _finalize() async {
    final id = _activeClipId;
    if (id == null) return;
    _phase = LocalRecordingPhase.finalizing;
    _recordTimer?.cancel();
    _limitTimer?.cancel();
    _recordTimer = null;
    _elapsed.stop();
    _changed();
    try {
      await _audio.stop();
      await _prepareClip(id);
      _failure = null;
    } finally {
      _activeClipId = null;
      _phase = LocalRecordingPhase.idle;
    }
  }

  Future<void> _prepareClip(String id) async {
    final clip = _capture!.clips.firstWhere((c) => c.id == id);
    final file = await _store.audioFile(_capture!, clip);
    if (!await file.exists() || await file.length() == 0) {
      throw StateError('Audio is incomplete.');
    }
    final duration = await _audio.inspect(file.path);
    if (duration <= Duration.zero) throw StateError('Audio is incomplete.');
    await _publish(
      _capture!.copyWith(
        clips: [
          for (final value in _capture!.clips)
            value.id == id
                ? value.withState(LocalClipState.ready, duration: duration)
                : value,
        ],
      ),
    );
  }

  Future<void> _recover() async {
    for (final clip in List<LocalAudioClip>.of(_capture!.clips)) {
      if (clip.state == LocalClipState.deleting) {
        await _delete(clip.id);
      } else if (clip.state == LocalClipState.pending) {
        try {
          await _prepareClip(clip.id);
        } on _SaveFailure {
          rethrow;
        } catch (_) {
          _failure = LocalCaptureFailure(
            LocalFailureKind.recording,
            'An unfinished clip is kept on this device. Retry checking it, or delete it if it cannot be played.',
            clipId: clip.id,
          );
        }
      }
    }
  }

  Future<void> retry() {
    if (!snapshot.canRetry) return Future.value();
    if (_capture == null) return initialize();
    return _run(
      () async {
        _failure = null;
        await _flush();
        await _recover();
      },
      LocalFailureKind.save,
      'Your Capture could not be saved. Existing notes and available audio are kept; retry.',
    );
  }

  Future<void> deleteClip(String id) {
    if (!snapshot.canDelete(id)) return Future.value();
    return _run(
      () async {
        await _stopPlayback();
        await _delete(id);
        _failure = null;
      },
      LocalFailureKind.save,
      'The clip could not be deleted completely. It is still listed; retry deletion.',
    );
  }

  Future<void> _delete(String id) async {
    var clip = _capture!.clips.firstWhere((c) => c.id == id);
    if (clip.state != LocalClipState.deleting) {
      // Keep the user's deletion intent in memory if its first write fails;
      // ordinary flush/retry can then publish it before touching any bytes.
      _capture = _capture!.copyWith(
        clips: [
          for (final value in _capture!.clips)
            value.id == id ? value.withState(LocalClipState.deleting) : value,
        ],
      );
      _dirty = true;
      await _publish(_capture!);
      clip = _capture!.clips.firstWhere((c) => c.id == id);
    }
    await _store.deleteAudio(_capture!, clip);
    await _publish(
      _capture!.copyWith(
        clips: _capture!.clips.where((c) => c.id != id).toList(),
      ),
    );
  }

  Future<void> playClip(String id) {
    if (!snapshot.canPlay(id)) return Future.value();
    return _run(
      () async {
        await _stopPlayback();
        final clip = _capture!.clips.firstWhere((c) => c.id == id);
        final file = await _store.audioFile(_capture!, clip);
        if (!await file.exists()) throw StateError('Audio is unavailable.');
        final intent = ++_playIntent;
        _playingClipId = id;
        _failure = null;
        try {
          await _audio.play(
            file.path,
            onComplete: () => _playEnded(intent, false),
            onError: () => _playEnded(intent, true),
          );
        } catch (_) {
          await _stopPlayback();
          rethrow;
        }
      },
      LocalFailureKind.playback,
      'This clip could not be played. Your saved Capture has not been removed.',
    );
  }

  void _playEnded(int intent, bool failed) {
    if (_playIntent != intent) return;
    if (failed) {
      _failure = const LocalCaptureFailure(
        LocalFailureKind.playback,
        'Playback stopped unexpectedly. Your saved clip is still here.',
      );
    }
    unawaited(stopPlayback());
  }

  Future<void> _stopPlayback() async {
    _playIntent++;
    _playingClipId = null;
    await _audio.stopPlayback();
  }

  Future<void> stopPlayback() => _run(
    _stopPlayback,
    LocalFailureKind.playback,
    'Playback could not be stopped. Try again.',
  );

  Future<void> onLifecycleChanged(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) {
      if (_resume case final value? when !value.isCompleted) value.complete();
      _changed();
      return Future.value();
    }
    if (state == AppLifecycleState.inactive &&
        _phase == LocalRecordingPhase.requestingPermission) {
      // This queued flush must not stop a recording that begins after the
      // permission dialog returns and focus is restored.
      return flush();
    }
    if (state != AppLifecycleState.inactive ||
        _phase != LocalRecordingPhase.requestingPermission) {
      _cancelIntent();
    }
    _changed();
    return _run(
      () async {
        await _stopPlayback();
        await _finalize();
        await _flush();
      },
      LocalFailureKind.save,
      'Your Capture has unsaved changes. Available input and audio are kept; retry.',
    );
  }

  Future<void> suspend() {
    _lifecycle = AppLifecycleState.hidden;
    _cancelIntent();
    return _run(
      () async {
        await _stopPlayback();
        await _finalize();
        await _flush();
      },
      LocalFailureKind.save,
      'Your Capture has unsaved changes. Available input and audio are kept; retry.',
    );
  }

  Future<void> close() {
    if (_closing) return _tail;
    _closing = true;
    _cancelIntent();
    _notesTimer?.cancel();
    return _run(
      () async {
        try {
          await _finalize();
          await _flush();
        } finally {
          await _audio.close();
        }
      },
      LocalFailureKind.save,
      'Some changes could not be saved.',
      allowClosing: true,
    ).whenComplete(() {
      _recordTimer?.cancel();
      _limitTimer?.cancel();
      _closed = true;
      super.dispose();
    });
  }
}
