import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'capture_input_panel.dart';
import 'capture_notes_formatter.dart';
import 'capture_notice.dart';
import 'capture_view_data.dart';

/// A controlled Capture surface. Its only local state is native text editing.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    super.key,
    required this.data,
    required this.onNotesChanged,
    required this.onDeleteClip,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onStartBlank,
    required this.onExtract,
    required this.onBack,
  });

  final CaptureViewData data;
  final ValueChanged<String> onNotesChanged;
  final ValueChanged<String> onDeleteClip;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final VoidCallback onStartBlank;
  final VoidCallback onExtract;
  final VoidCallback onBack;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  late final _notesController = TextEditingController(text: widget.data.notes);
  late final _notesFormatter = CaptureNotesFormatter(widget.data.notes);

  @override
  void didUpdateWidget(CaptureScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.notes != widget.data.notes &&
        _notesController.text != widget.data.notes) {
      final offset = math.max(
        0,
        math.min(
          _notesController.selection.extentOffset,
          widget.data.notes.length,
        ),
      );
      _notesController.value = TextEditingValue(
        text: widget.data.notes,
        selection: TextSelection.collapsed(offset: offset),
      );
      _notesFormatter.reset(widget.data.notes);
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Go back',
            onPressed: widget.onBack,
            icon: const BackButtonIcon(),
          ),
          Expanded(
            child: Text(
              'Capture Job Notes',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    final input = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.data.notice case final notice?) ...[
          CaptureNoticeView(notice: notice),
          const SizedBox(height: 16),
        ],
        CaptureInputPanel(
          data: widget.data,
          notesController: _notesController,
          notesFormatter: _notesFormatter,
          onNotesChanged: widget.onNotesChanged,
          onDeleteClip: widget.onDeleteClip,
          onStartRecording: widget.onStartRecording,
          onStopRecording: widget.onStopRecording,
          onStartBlank: widget.onStartBlank,
        ),
      ],
    );
    final footer = ColoredBox(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: widget.data.canExtract && !widget.data.inputLocked
                  ? widget.onExtract
                  : null,
              child: const Text('Extract Line Items'),
            ),
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Short windows need one scroll path, rather than competing fixed chrome.
        if (constraints.maxHeight < 360) {
          return SingleChildScrollView(
            child: Column(
              children: [
                header,
                Padding(padding: const EdgeInsets.all(16), child: input),
                footer,
              ],
            ),
          );
        }
        return Column(
          children: [
            header,
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: input,
              ),
            ),
            footer,
          ],
        );
      },
    );
  }
}
