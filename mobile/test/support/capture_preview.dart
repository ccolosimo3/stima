import 'package:flutter/material.dart';

import 'package:stima_mobile/features/capture/presentation/capture_screen.dart';
import 'package:stima_mobile/features/capture/presentation/capture_view_data.dart';

enum CapturePreviewScenario {
  empty('Empty'),
  notes('Notes only'),
  populated('Notes and clips'),
  starting('Starting'),
  recording('Recording'),
  clipLimit('Five clips'),
  saving('Saving locally'),
  saved('Saved locally'),
  saveError('Local save error'),
  microphoneDenied('Microphone denied'),
  microphoneUnavailable('Microphone unavailable'),
  interrupted('Recording interrupted'),
  extracting('Extraction busy'),
  extractionError('Extraction error');

  const CapturePreviewScenario(this.label);
  final String label;
}

/// An in-memory caller, deliberately separate from operational capture owners.
class CapturePreview extends StatefulWidget {
  const CapturePreview({
    super.key,
    required this.onToggleTheme,
    this.initialScenario = CapturePreviewScenario.populated,
  });

  final VoidCallback onToggleTheme;
  final CapturePreviewScenario initialScenario;

  @override
  State<CapturePreview> createState() => _CapturePreviewState();
}

class _CapturePreviewState extends State<CapturePreview> {
  static const _exampleNotes =
      'Spread 5 yards of brown mulch. Trim 8 shrubs. Haul debris.\n'
      'Mulch \$450, trimming \$160, haul \$90.';
  static const _exampleClips = [
    CaptureClip(id: 'mulch-note', number: 1, duration: Duration(seconds: 28)),
    CaptureClip(id: 'shrubs-note', number: 2, duration: Duration(seconds: 16)),
  ];

  String _notes = _exampleNotes;
  List<CaptureClip> _clips = List.of(_exampleClips);
  CaptureRecordingPhase _phase = CaptureRecordingPhase.idle;
  bool _locked = false;
  bool _canRecord = true;
  CaptureNotice? _notice;
  CaptureNotice? _microphoneNotice;
  String _request = 'Choose a preview state. No data leaves this screen.';
  late CapturePreviewScenario _scenario;

  @override
  void initState() {
    super.initState();
    _applyScenario(widget.initialScenario);
  }

  void _applyScenario(CapturePreviewScenario scenario) {
    _scenario = scenario;
    _phase = switch (scenario) {
      CapturePreviewScenario.starting => CaptureRecordingPhase.starting,
      CapturePreviewScenario.recording => CaptureRecordingPhase.recording,
      _ => CaptureRecordingPhase.idle,
    };
    _locked = scenario == CapturePreviewScenario.extracting;
    _canRecord =
        scenario != CapturePreviewScenario.microphoneDenied &&
        scenario != CapturePreviewScenario.microphoneUnavailable;
    if (scenario == CapturePreviewScenario.empty) {
      _notes = '';
      _clips = [];
    } else if (scenario == CapturePreviewScenario.notes) {
      _notes = _exampleNotes;
      _clips = [];
    } else if (scenario == CapturePreviewScenario.populated) {
      _notes = _exampleNotes;
      _clips = List.of(_exampleClips);
    } else if (scenario == CapturePreviewScenario.clipLimit) {
      _clips = List.generate(
        5,
        (index) => CaptureClip(
          id: 'limit-clip-$index',
          number: index + 1,
          duration: Duration(seconds: 12 + index),
        ),
      );
    }
    _notice = switch (scenario) {
      CapturePreviewScenario.saving => const CaptureNotice(
        'Saving on this device…',
      ),
      CapturePreviewScenario.saved => const CaptureNotice(
        'Saved on this device.',
      ),
      CapturePreviewScenario.saveError => const CaptureNotice(
        'Stima could not save this capture. Copy your notes before leaving.',
        tone: CaptureNoticeTone.error,
      ),
      CapturePreviewScenario.extracting => const CaptureNotice(
        'Extraction in progress. Submitted notes and clips are locked.',
      ),
      CapturePreviewScenario.extractionError => const CaptureNotice(
        'Extraction failed. Your notes and clips are still here. You can edit and try again.',
        tone: CaptureNoticeTone.error,
      ),
      _ => null,
    };
    _microphoneNotice = switch (scenario) {
      CapturePreviewScenario.microphoneDenied => const CaptureNotice(
        'Microphone access denied. You can still type notes.',
        tone: CaptureNoticeTone.warning,
      ),
      CapturePreviewScenario.microphoneUnavailable => const CaptureNotice(
        'Microphone unavailable. You can still type notes.',
        tone: CaptureNoticeTone.warning,
      ),
      CapturePreviewScenario.interrupted => const CaptureNotice(
        'Recording stopped when you left the app. No saved clip is claimed by this preview.',
        tone: CaptureNoticeTone.warning,
      ),
      _ => null,
    };
    _request =
        'Preview state: ${scenario.label}. No real capture operation ran.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = CaptureViewData(
      notes: _notes,
      clips: _clips,
      recordingPhase: _phase,
      elapsed: const Duration(seconds: 28),
      inputLocked: _locked,
      canRecord: _canRecord,
      canExtract:
          (_notes.trim().isNotEmpty || _clips.isNotEmpty) &&
          _phase == CaptureRecordingPhase.idle &&
          !_locked,
      canStartBlank: _phase == CaptureRecordingPhase.idle && !_locked,
      notice: _notice,
      microphoneNotice: _microphoneNotice,
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
                        PopupMenuButton<CapturePreviewScenario>(
                          tooltip: 'Preview state',
                          initialValue: _scenario,
                          onSelected: (scenario) =>
                              setState(() => _applyScenario(scenario)),
                          itemBuilder: (_) => [
                            for (final scenario
                                in CapturePreviewScenario.values)
                              PopupMenuItem(
                                value: scenario,
                                child: Text(scenario.label),
                              ),
                          ],
                          icon: const Icon(Icons.tune),
                        ),
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
                      'UI preview · synthetic data. Recording, saving and extraction are simulated.',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _request,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: CaptureScreen(
                data: data,
                onNotesChanged: (notes) => setState(() {
                  _notes = notes;
                  _notice = const CaptureNotice(
                    'Edited in this preview. Saving is simulated.',
                  );
                }),
                onDeleteClip: (id) => setState(() {
                  _clips = _clips.where((clip) => clip.id != id).toList();
                  _request = 'Clip removed from this preview. No audio file was deleted.';
                }),
                onStartRecording: () => setState(() {
                  _phase = CaptureRecordingPhase.starting;
                  _request = 'Start requested. Choose Recording to simulate the next state.';
                }),
                onStopRecording: () => setState(() {
                  _phase = CaptureRecordingPhase.idle;
                  _request = 'Stop requested. This preview recorded no audio.';
                }),
                onStartBlank: () => setState(() {
                  _request =
                      'Start blank requested. No Quote Draft was created.';
                }),
                onExtract: () => setState(() {
                  _applyScenario(CapturePreviewScenario.extracting);
                  _request = 'Extract requested. No data was sent. Choose Extraction error to unlock.';
                }),
                onBack: () => setState(() {
                  _request = 'Back requested. This preview stays open.';
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
