import 'dart:async';

import 'package:flutter/material.dart';

import '../application/local_capture_controller.dart';
import '../application/local_capture_snapshot.dart';
import '../data/local_capture_audio.dart';
import '../data/local_capture_store.dart';
import '../domain/local_capture.dart';
import 'capture_screen.dart';
import 'capture_view_data.dart';

/// Composes one real Capture and forwards lifecycle events after native editing.
/// Recording, eligibility, files and recovery remain with the controller.
class LocalCapturePage extends StatefulWidget {
  const LocalCapturePage({
    super.key,
    required this.onToggleTheme,
    this.createController,
  });

  final VoidCallback onToggleTheme;
  final Future<LocalCaptureController> Function()? createController;

  @override
  State<LocalCapturePage> createState() => _LocalCapturePageState();
}

class _LocalCapturePageState extends State<LocalCapturePage>
    with WidgetsBindingObserver {
  final _editing = GlobalKey<CaptureScreenState>();
  LocalCaptureController? _controller;
  late AppLifecycleState _lifecycle;
  bool _openFailed = false;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    _lifecycle =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.detached;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_open());
  }

  Future<void> _open() async {
    setState(() => _openFailed = false);
    try {
      final controller = await (widget.createController?.call() ?? _create());
      if (!mounted) {
        await controller.close();
        return;
      }
      _controller = controller;
      controller.addListener(_refresh);
      await controller.onLifecycleChanged(_lifecycle);
      await controller.initialize();
    } catch (_) {
      if (mounted) setState(() => _openFailed = true);
    }
  }

  Future<LocalCaptureController> _create() async => LocalCaptureController(
    store: await LocalCaptureStore.openAppStore(),
    audio: NativeLocalCaptureAudio(),
  );

  void _refresh() {
    if (mounted && _active) setState(() {});
  }

  void _request(Future<void> Function() command) {
    _editing.currentState?.flushNotes();
    unawaited(command());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    // Publish accepted visible composition synchronously before core suspension.
    _editing.currentState?.flushNotes();
    final controller = _controller;
    if (controller != null) unawaited(controller.onLifecycleChanged(state));
  }

  @override
  void deactivate() {
    _active = false;
    _editing.currentState?.flushNotes();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_refresh);
      unawaited(controller.close());
    }
    super.dispose();
  }

  CaptureNotice _notice(LocalCaptureSnapshot? snapshot) {
    if (_openFailed) {
      return const CaptureNotice(
        'Device storage could not be opened. Nothing has been replaced. Retry opening your Capture.',
        tone: CaptureNoticeTone.error,
      );
    }
    if (snapshot == null || snapshot.saveState == LocalSaveState.loading) {
      return const CaptureNotice('Opening saved Capture…');
    }
    if (snapshot.failure case final failure?) {
      return CaptureNotice(
        failure.message,
        tone: failure.kind == LocalFailureKind.permission
            ? CaptureNoticeTone.warning
            : CaptureNoticeTone.error,
      );
    }
    if (snapshot.saveState == LocalSaveState.pending) {
      return const CaptureNotice('Saving on this device…');
    }
    if (snapshot.recordingPhase == LocalRecordingPhase.recording ||
        snapshot.recordingPhase == LocalRecordingPhase.starting) {
      return const CaptureNotice(
        'Notes saved on this device. Stop to finish the recording.',
      );
    }
    if (snapshot.recordingPhase == LocalRecordingPhase.finalizing) {
      return const CaptureNotice('Finishing and saving recording…');
    }
    if (snapshot.clips.any((clip) => clip.state != LocalClipState.ready)) {
      return const CaptureNotice(
        'Some clips are unfinished. Available audio is kept; retry checking it or delete the unfinished clip.',
        tone: CaptureNoticeTone.warning,
      );
    }
    return const CaptureNotice('Saved on this device.');
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final snapshot = controller?.snapshot;
    final theme = Theme.of(context);
    CaptureClip displayClip(LocalAudioClip clip) => CaptureClip(
      id: clip.id,
      number: clip.number,
      duration: clip.duration,
      status: switch (clip.state) {
        LocalClipState.ready => null,
        LocalClipState.deleting => 'Deletion pending',
        LocalClipState.pending => switch (snapshot!.recordingPhase) {
          LocalRecordingPhase.recording => 'Recording',
          LocalRecordingPhase.starting => 'Starting',
          LocalRecordingPhase.finalizing => 'Finishing',
          _ => 'Unfinished · not ready to play',
        },
      },
      canPlay: snapshot!.canPlay(clip.id),
      canDelete: snapshot.canDelete(clip.id),
      playing: snapshot.playingClipId == clip.id,
    );
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: theme.colorScheme.surfaceContainerLowest,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Stima', style: theme.textTheme.titleMedium),
                        const Spacer(),
                        IconButton(
                          tooltip: theme.brightness == Brightness.dark
                              ? 'Switch to light theme'
                              : 'Switch to dark theme',
                          onPressed: widget.onToggleTheme,
                          icon: Icon(
                            theme.brightness == Brightness.dark
                                ? Icons.light_mode_outlined
                                : Icons.dark_mode_outlined,
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      'Device-local Capture. This app does not upload or sync. Sign-in and Extraction are not available yet.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: CaptureScreen(
                key: _editing,
                data: CaptureViewData(
                  notes: snapshot?.notes ?? '',
                  clips: [
                    for (final clip in snapshot?.clips ?? <LocalAudioClip>[])
                      if (clip.state == LocalClipState.ready) displayClip(clip),
                  ],
                  pendingClips: [
                    for (final clip in snapshot?.clips ?? <LocalAudioClip>[])
                      if (clip.state != LocalClipState.ready) displayClip(clip),
                  ],
                  recordingPhase: switch (snapshot?.recordingPhase) {
                    LocalRecordingPhase.requestingPermission ||
                    LocalRecordingPhase.starting =>
                      CaptureRecordingPhase.starting,
                    LocalRecordingPhase.recording =>
                      CaptureRecordingPhase.recording,
                    LocalRecordingPhase.finalizing =>
                      CaptureRecordingPhase.finalizing,
                    _ => CaptureRecordingPhase.idle,
                  },
                  elapsed: snapshot?.elapsed ?? Duration.zero,
                  inputLocked: !(snapshot?.canEditNotes ?? false),
                  canRecord: snapshot?.canRecord ?? false,
                  canStopRecording: !(snapshot?.busy ?? true),
                  notice: _notice(snapshot),
                ),
                onNotesChanged: (notes) => controller?.updateNotes(notes),
                onStartRecording: () => _request(controller!.startRecording),
                onStopRecording: () => _request(controller!.stopRecording),
                onDeleteClip: (id) =>
                    _request(() => controller!.deleteClip(id)),
                onPlayClip: (id) => _request(() => controller!.playClip(id)),
                onStopPlayback: () => _request(controller!.stopPlayback),
                onRetry: _openFailed
                    ? () => unawaited(_open())
                    : snapshot?.canRetry == true && snapshot?.failure != null
                    ? () => _request(controller!.retry)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
