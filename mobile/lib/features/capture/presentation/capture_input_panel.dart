import 'package:flutter/material.dart';

import '../domain/local_capture.dart';
import 'capture_notes_formatter.dart';
import 'capture_notice.dart';
import 'capture_view_data.dart';

class CaptureInputPanel extends StatelessWidget {
  const CaptureInputPanel({
    super.key,
    required this.data,
    required this.notesController,
    required this.notesFormatter,
    required this.onDeleteClip,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onStartBlank,
    this.onPlayClip,
    this.onStopPlayback,
  });

  final CaptureViewData data;
  final TextEditingController notesController;
  final CaptureNotesFormatter notesFormatter;
  final ValueChanged<String> onDeleteClip;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final VoidCallback? onStartBlank;
  final ValueChanged<String>? onPlayClip;
  final VoidCallback? onStopPlayback;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final recording = data.recordingPhase == CaptureRecordingPhase.recording;
    final starting = data.recordingPhase == CaptureRecordingPhase.starting;
    final finalizing = data.recordingPhase == CaptureRecordingPhase.finalizing;
    final limitReached =
        data.clips.length + data.pendingClips.length >= captureMaxClips;
    final canStart =
        data.canRecord &&
        !data.inputLocked &&
        !starting &&
        !finalizing &&
        !limitReached;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('RECORDED CLIPS')),
                    Text('${data.clips.length} clips'),
                  ],
                ),
                const SizedBox(height: 8),
                if (data.clips.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No clips recorded yet',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
                for (final clip in data.clips) _clipRow(context, clip),
                if (data.pendingClips.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('IN PROGRESS / UNFINISHED'),
                  for (final clip in data.pendingClips) _clipRow(context, clip),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('WRITTEN DESCRIPTION'),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  readOnly: data.inputLocked,
                  minLines: 4,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Add any typed details here…',
                    labelText: 'Written description',
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                    alignLabelWithHint: true,
                  ),
                  inputFormatters: [notesFormatter],
                ),
                if (onStartBlank != null)
                  TextButton(
                    onPressed: data.canStartBlank && !data.inputLocked
                        ? onStartBlank
                        : null,
                    child: const Text('Start a blank document'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (data.microphoneNotice case final notice?) ...[
          CaptureNoticeView(notice: notice),
          const SizedBox(height: 12),
        ],
        Center(
          child: Column(
            children: [
              if (recording)
                Text('Recording · ${captureDuration(data.elapsed)}')
              else if (starting)
                const Text('Starting recording…')
              else if (finalizing)
                const Text('Finishing and saving recording…')
              else
                const Text('Speak another detail'),
              const SizedBox(height: 12),
              IconButton.filled(
                tooltip: recording ? 'Stop recording' : 'Start recording',
                onPressed: recording
                    ? (data.inputLocked || !data.canStopRecording
                          ? null
                          : onStopRecording)
                    : (canStart ? onStartRecording : null),
                style: IconButton.styleFrom(
                  fixedSize: const Size(80, 80),
                  backgroundColor: recording ? colors.secondaryContainer : null,
                  foregroundColor: recording
                      ? colors.onSecondaryContainer
                      : null,
                ),
                icon: Icon(recording ? Icons.stop : Icons.mic_none, size: 32),
              ),
              const SizedBox(height: 8),
              Text(
                finalizing
                    ? 'Please wait'
                    : recording
                    ? 'Stop recording'
                    : 'Start recording',
              ),
              if (limitReached && !recording)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Maximum 5 clips reached.'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _clipRow(BuildContext context, CaptureClip clip) {
    return Padding(
      key: ValueKey(clip.id),
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Clip ${clip.number} · ${clip.status ?? captureDuration(clip.duration)}',
                ),
              ),
              if (clip.status == null && onPlayClip != null)
                IconButton(
                  tooltip: clip.playing
                      ? 'Stop clip ${clip.number}'
                      : 'Play clip ${clip.number}',
                  onPressed: clip.canPlay && !data.inputLocked
                      ? clip.playing
                            ? onStopPlayback
                            : () => onPlayClip!(clip.id)
                      : null,
                  icon: Icon(clip.playing ? Icons.stop : Icons.play_arrow),
                ),
              IconButton(
                tooltip: 'Delete clip ${clip.number}',
                onPressed:
                    data.canDeleteClips && clip.canDelete && !data.inputLocked
                    ? () => onDeleteClip(clip.id)
                    : null,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
