import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stima_mobile/features/capture/application/local_capture_controller.dart';
import 'package:stima_mobile/features/capture/application/local_capture_snapshot.dart';
import 'package:stima_mobile/features/capture/data/local_capture_audio.dart';
import 'package:stima_mobile/features/capture/data/local_capture_store.dart';
import 'package:stima_mobile/features/capture/domain/local_capture.dart';

class ControlledStore extends LocalCaptureStore {
  ControlledStore(super.directory);
  Completer<void>? saveGate;
  Completer<void>? enteredSave;
  bool failNext = false;

  @override
  Future<void> save(LocalCapture capture) async {
    enteredSave?.complete();
    enteredSave = null;
    final gate = saveGate;
    saveGate = null;
    if (gate != null) await gate.future;
    if (failNext) {
      failNext = false;
      // Exercise a real failed filesystem write at the production repository.
      final held = await directory.rename('${directory.path}-held');
      await File(directory.path).writeAsString('blocked');
      try {
        await super.save(capture);
      } finally {
        await File(directory.path).delete();
        await held.rename(directory.path);
      }
    } else {
      await super.save(capture);
    }
  }
}

class TestAudio implements LocalCaptureAudio {
  Completer<bool>? permission;
  Completer<void>? enteredPermission;
  Completer<void>? startGate;
  Completer<void>? enteredStart;
  bool granted = true;
  bool invalidAudio = false;
  bool failStop = false;
  bool failPlay = false;
  bool recording = false;
  bool playing = false;
  String? path;
  final interruptions = <void Function()>[];
  void Function()? completed;
  void Function()? playbackError;

  @override
  Future<bool> requestPermission() async {
    enteredPermission?.complete();
    return permission != null ? await permission!.future : granted;
  }

  @override
  Future<void> start(
    String path, {
    required void Function() onInterruption,
  }) async {
    this.path = path;
    interruptions.add(onInterruption);
    enteredStart?.complete();
    if (startGate != null) await startGate!.future;
    await File(path).writeAsBytes([11, 22, 33, 44, 55], flush: true);
    recording = true;
  }

  @override
  Future<void> stop() async {
    recording = false;
    if (failStop) {
      failStop = false;
      throw StateError('synthetic native stop failure');
    }
  }

  @override
  Future<Duration> inspect(String path) async {
    if (invalidAudio) throw StateError('synthetic incomplete container');
    return const Duration(seconds: 4);
  }

  @override
  Future<void> play(
    String path, {
    required void Function() onComplete,
    required void Function() onError,
  }) async {
    if (failPlay) throw StateError('synthetic playback failure');
    completed = onComplete;
    playbackError = onError;
    playing = true;
  }

  @override
  Future<void> stopPlayback() async {
    playing = false;
  }

  @override
  Future<void> close() async {
    recording = false;
    playing = false;
  }
}

void main() {
  late Directory directory;
  late ControlledStore store;
  late TestAudio audio;
  late LocalCaptureController controller;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'stima-capture-controller-',
    );
    store = ControlledStore(directory);
    audio = TestAudio();
    controller = LocalCaptureController(
      store: store,
      audio: audio,
      notesDebounce: const Duration(days: 1),
    );
    await controller.onLifecycleChanged(AppLifecycleState.resumed);
    await controller.initialize();
  });
  tearDown(() async {
    await controller.close();
    await directory.delete(recursive: true);
  });

  test('older write cannot acknowledge newer notes; real write failure retains and retries', () async {
    controller.updateNotes('first');
    final entered = store.enteredSave = Completer<void>();
    final gate = store.saveGate = Completer<void>();
    final saving = controller.flush();
    await entered.future;
    controller.updateNotes('latest 🧰');
    gate.complete();
    await saving;
    expect(controller.snapshot.notes, 'latest 🧰');
    expect(controller.snapshot.saveState, LocalSaveState.pending);
    expect((await LocalCaptureStore(directory).load()).notes, 'first');
    store.failNext = true;
    await controller.flush();
    expect(controller.snapshot.saveState, LocalSaveState.error);
    expect(controller.snapshot.notes, 'latest 🧰');
    expect((await LocalCaptureStore(directory).load()).notes, 'first');
    await controller.retry();
    expect(controller.snapshot.saveState, LocalSaveState.saved);
    expect((await LocalCaptureStore(directory).load()).notes, 'latest 🧰');
  });

  test('one Start survives its permission dialog, then interruption saves the same file', () async {
    audio.permission = Completer<bool>();
    audio.enteredPermission = Completer<void>();
    final start = controller.startRecording();
    await audio.enteredPermission!.future;
    final inactive = controller.onLifecycleChanged(AppLifecycleState.inactive);
    audio.permission!.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(audio.recording, false);
    await controller.onLifecycleChanged(AppLifecycleState.resumed);
    await start;
    await inactive;
    expect(audio.recording, true);
    expect(controller.snapshot.recordingPhase, LocalRecordingPhase.recording);
    final id = controller.snapshot.clips.single.id;
    expect(controller.snapshot.clips.single.state, LocalClipState.pending);
    await controller.onLifecycleChanged(AppLifecycleState.inactive);
    expect(audio.recording, false);
    expect(controller.snapshot.clips.single.state, LocalClipState.ready);
    await controller.onLifecycleChanged(AppLifecycleState.resumed);
    expect(audio.recording, false);
    final restored = await LocalCaptureStore(directory).load();
    expect(restored.clips.single.id, id);
    expect(await File(audio.path!).readAsBytes(), [11, 22, 33, 44, 55]);
  });

  test('background before permission completion cancels intent without opening microphone', () async {
    audio.permission = Completer<bool>();
    audio.enteredPermission = Completer<void>();
    final start = controller.startRecording();
    await audio.enteredPermission!.future;
    final leaving = controller.onLifecycleChanged(AppLifecycleState.hidden);
    audio.permission!.complete(true);
    await start;
    await leaving;
    await controller.onLifecycleChanged(AppLifecycleState.resumed);
    expect(audio.path, isNull);
    expect(controller.snapshot.clips, isEmpty);
    expect(controller.snapshot.canRecord, true);
  });

  test('late native Start acknowledgement stops; old callbacks cannot affect a new clip', () async {
    audio.startGate = Completer<void>();
    audio.enteredStart = Completer<void>();
    final start = controller.startRecording();
    await audio.enteredStart!.future;
    final leaving = controller.onLifecycleChanged(AppLifecycleState.paused);
    audio.startGate!.complete();
    await start;
    await leaving;
    expect(audio.recording, false);
    final first = controller.snapshot.clips.single.id;
    await controller.onLifecycleChanged(AppLifecycleState.resumed);
    audio.startGate = null;
    audio.enteredStart = null;
    await controller.startRecording();
    final second = controller.snapshot.clips.last.id;
    expect(second, isNot(first));
    audio.interruptions.first();
    await Future<void>.delayed(Duration.zero);
    expect(audio.recording, true);
    await controller.stopRecording();
    expect(controller.snapshot.clips.map((c) => c.number), [1, 2]);
  });

  test('finalize publication failure retains pending identity and bytes; retry adds no duplicate', () async {
    await controller.startRecording();
    final id = controller.snapshot.clips.single.id;
    final path = audio.path!;
    store.failNext = true;
    await controller.stopRecording();
    expect(controller.snapshot.clips.single.state, LocalClipState.pending);
    expect(controller.snapshot.saveState, LocalSaveState.error);
    expect(await File(path).readAsBytes(), [11, 22, 33, 44, 55]);
    await controller.retry();
    expect(controller.snapshot.clips.single.id, id);
    expect(controller.snapshot.clips.single.state, LocalClipState.ready);
    expect((await LocalCaptureStore(directory).load()).clips.single.id, id);
  });

  test('unusable or failed-stop bytes stay pending across reopen until explicit delete', () async {
    await controller.startRecording();
    final path = audio.path!;
    final id = controller.snapshot.clips.single.id;
    audio.failStop = true;
    await controller.stopRecording();
    expect(controller.snapshot.clips.single.state, LocalClipState.pending);
    audio.invalidAudio = true;
    await controller.close();
    controller = LocalCaptureController(
      store: LocalCaptureStore(directory),
      audio: audio,
    );
    await controller.onLifecycleChanged(AppLifecycleState.resumed);
    await controller.initialize();
    expect(controller.snapshot.clips.single.id, id);
    expect(controller.snapshot.clips.single.state, LocalClipState.pending);
    expect(controller.snapshot.failure, isNotNull);
    expect(await File(path).exists(), true);
    await controller.deleteClip(id);
    expect(controller.snapshot.clips, isEmpty);
    expect(await File(path).exists(), false);
    expect((await LocalCaptureStore(directory).load()).clips, isEmpty);
  });

  test(
    'failed deletion keeps row; reopening converges persisted deletion intent',
    () async {
      await controller.startRecording();
      await controller.stopRecording();
      final clip = controller.snapshot.clips.single;
      final file = File(audio.path!);
      await file.delete();
      await Directory(file.path)
          .create(); // real unlink failure, not a fake success
      await controller.deleteClip(clip.id);
      expect(controller.snapshot.clips.single.state, LocalClipState.deleting);
      expect(controller.snapshot.canPlay(clip.id), false);
      await Directory(file.path).delete();
      await controller.close();
      controller = LocalCaptureController(
        store: LocalCaptureStore(directory),
        audio: audio,
      );
      await controller.onLifecycleChanged(AppLifecycleState.resumed);
      await controller.initialize();
      expect(controller.snapshot.clips, isEmpty);
      expect((await LocalCaptureStore(directory).load()).clips, isEmpty);
    },
  );

  test('play failure retains clip; recording stops playback and enforces five clips', () async {
    for (var i = 0; i < captureMaxClips; i++) {
      await controller.startRecording();
      await controller.stopRecording();
      if (i == 0) {
        final id = controller.snapshot.clips.single.id;
        audio.failPlay = true;
        await controller.playClip(id);
        expect(controller.snapshot.clips.single.id, id);
        expect(controller.snapshot.failure?.kind, LocalFailureKind.playback);
        audio.failPlay = false;
        await controller.playClip(id);
        expect(audio.playing, true);
      }
    }
    expect(audio.playing, false);
    expect(controller.snapshot.canRecord, false);
    await controller.startRecording();
    expect(controller.snapshot.clips.length, captureMaxClips);
    await controller.deleteClip(controller.snapshot.clips.first.id);
    await controller.startRecording();
    await controller.stopRecording();
    expect(controller.snapshot.clips.map((c) => c.number), [2, 3, 4, 5, 6]);
  });

  test('denied permission leaves notes usable; duplicate Start/Stop remains single flight', () async {
    audio.granted = false;
    await controller.startRecording();
    expect(controller.snapshot.failure?.kind, LocalFailureKind.permission);
    controller.updateNotes('typed without microphone');
    await controller.flush();
    expect(
      (await LocalCaptureStore(directory).load()).notes,
      'typed without microphone',
    );
    audio.granted = true;
    final first = controller.startRecording();
    final duplicate = controller.startRecording();
    await Future.wait([first, duplicate]);
    await Future.wait([controller.stopRecording(), controller.stopRecording()]);
    expect(controller.snapshot.clips.length, 1);
    expect(controller.snapshot.clips.single.state, LocalClipState.ready);
  });

  test(
    'close during permission preserves notes without late offscreen recording',
    () async {
      controller.updateNotes('keep these pending notes');
      audio.permission = Completer<bool>();
      audio.enteredPermission = Completer<void>();
      final start = controller.startRecording();
      await audio.enteredPermission!.future;
      final closing = controller.close();
      audio.permission!.complete(true);
      await start;
      await closing;
      expect(audio.path, isNull);
      expect(
        (await LocalCaptureStore(directory).load()).notes,
        'keep these pending notes',
      );
    },
  );

  test('late playback completion is ignored and asynchronous error retains saved membership', () async {
    await controller.startRecording();
    await controller.stopRecording();
    final id = controller.snapshot.clips.single.id;
    await controller.playClip(id);
    final staleComplete = audio.completed!;
    await controller.stopPlayback();
    await controller.playClip(id);
    staleComplete();
    expect(controller.snapshot.playingClipId, id);
    audio.playbackError!();
    await controller.flush();
    expect(controller.snapshot.playingClipId, isNull);
    expect(controller.snapshot.failure?.kind, LocalFailureKind.playback);
    expect((await LocalCaptureStore(directory).load()).clips.single.id, id);
  });

  test('deletion publication failure retries the same user intent before unlinking', () async {
    await controller.startRecording();
    await controller.stopRecording();
    final id = controller.snapshot.clips.single.id;
    final path = audio.path!;
    store.failNext = true;
    await controller.deleteClip(id);
    expect(controller.snapshot.clips.single.state, LocalClipState.deleting);
    expect(await File(path).exists(), true);
    expect(
      (await LocalCaptureStore(directory).load()).clips.single.state,
      LocalClipState.ready,
    );
    await controller.retry();
    expect(controller.snapshot.clips, isEmpty);
    expect(await File(path).exists(), false);
    expect((await LocalCaptureStore(directory).load()).clips, isEmpty);
  });

  test(
    'ordinary note editing autosaves without an explicit flush command',
    () async {
      await controller.close();
      controller = LocalCaptureController(
        store: store,
        audio: audio,
        notesDebounce: const Duration(milliseconds: 1),
      );
      await controller.initialize();
      final saved = Completer<void>();
      controller.addListener(() {
        if (controller.snapshot.notes == 'autosaved' &&
            controller.snapshot.saveState == LocalSaveState.saved &&
            !saved.isCompleted) {
          saved.complete();
        }
      });
      controller.updateNotes('autosaved');
      await saved.future.timeout(const Duration(seconds: 3));
      expect((await LocalCaptureStore(directory).load()).notes, 'autosaved');
    },
  );

  test(
    'the duration limit uses the ordinary stop and durable finalize path',
    () async {
      await controller.close();
      controller = LocalCaptureController(
        store: store,
        audio: audio,
        recordingLimit: const Duration(milliseconds: 10),
      );
      await controller.onLifecycleChanged(AppLifecycleState.resumed);
      await controller.initialize();
      final saved = Completer<void>();
      controller.addListener(() {
        if (controller.snapshot.clips.any(
              (clip) => clip.state == LocalClipState.ready,
            ) &&
            !saved.isCompleted) {
          saved.complete();
        }
      });
      await controller.startRecording();
      await saved.future.timeout(const Duration(seconds: 3));
      await controller.flush();
      expect(audio.recording, false);
      expect(controller.snapshot.recordingPhase, LocalRecordingPhase.idle);
      expect(
        (await LocalCaptureStore(directory).load()).clips.single.state,
        LocalClipState.ready,
      );
    },
  );
}
