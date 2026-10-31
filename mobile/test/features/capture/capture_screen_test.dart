import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stima_mobile/app/stima_app.dart';
import 'package:stima_mobile/app/theme/stima_theme.dart';
import 'package:stima_mobile/features/capture/presentation/capture_preview.dart';
import 'package:stima_mobile/features/capture/presentation/capture_screen.dart';
import 'package:stima_mobile/features/capture/presentation/capture_view_data.dart';

const _clips = [
  CaptureClip(id: 'first-audio', number: 1, duration: Duration(seconds: 28)),
  CaptureClip(id: 'second-audio', number: 2, duration: Duration(seconds: 16)),
];

void _viewport(WidgetTester tester, Size size, {double keyboard = 0}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);
}

Widget _preview(CapturePreviewScenario scenario) => MaterialApp(
  theme: stimaTheme(Brightness.dark),
  home: CapturePreview(initialScenario: scenario, onToggleTheme: () {}),
);

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Preview state'));
  await tester.pumpAndSettle();
  final option = find.text(label).last;
  await tester.ensureVisible(option);
  await tester.tap(option);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

IconButton _namedIconButton(WidgetTester tester, String label) =>
    tester.widget<IconButton>(
      find
          .ancestor(
            of: find.byTooltip(label),
            matching: find.byType(IconButton),
          )
          .first,
    );

Widget _screen(
  CaptureViewData data, {
  ValueChanged<String>? onNotesChanged,
  VoidCallback? onStart,
  ValueChanged<String>? onDelete,
}) => CaptureScreen(
  data: data,
  onNotesChanged: onNotesChanged ?? (_) {},
  onDeleteClip: onDelete ?? (_) {},
  onStartRecording: onStart ?? () {},
  onStopRecording: () {},
  onStartBlank: () {},
  onExtract: () {},
  onBack: () {},
);

void main() {
  testWidgets(
    'notes stay visible and starting accepts only one Start request with a keyboard inset',
    (tester) async {
      _viewport(tester, const Size(360, 800), keyboard: 300);
      var notes = '';
      var phase = CaptureRecordingPhase.idle;
      var starts = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: stimaTheme(Brightness.dark),
          home: Scaffold(
            body: SafeArea(
              child: StatefulBuilder(
                builder: (context, update) => Column(
                  children: [
                    Expanded(
                      child: _screen(
                        CaptureViewData(notes: notes, recordingPhase: phase),
                        onNotesChanged: (value) => update(() => notes = value),
                        onStart: () => update(() {
                          starts++;
                          phase = CaptureRecordingPhase.starting;
                        }),
                      ),
                    ),
                    Text('Accepted Start requests: $starts'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Mulch by the front path');
      await tester.pump();
      await _tap(tester, find.byTooltip('Start recording'));
      expect(find.text('Starting recording…'), findsOneWidget);
      expect(find.text('Accepted Start requests: 1'), findsOneWidget);
      await _tap(tester, find.byTooltip('Start recording'));
      expect(find.text('Accepted Start requests: 1'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Mulch by the front path',
      );
      await tester.ensureVisible(find.text('Extract Line Items'));
      expect(find.text('Extract Line Items').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the real preview enables notes-only Extraction after meaningful input',
    (tester) async {
      _viewport(tester, const Size(360, 800));
      await tester.pumpWidget(_preview(CapturePreviewScenario.empty));
      final extract = find.widgetWithText(FilledButton, 'Extract Line Items');
      expect(tester.widget<FilledButton>(extract).onPressed, isNull);
      await tester.enterText(find.byType(TextField), '  \n ');
      await tester.pump();
      expect(tester.widget<FilledButton>(extract).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'Haul the storm debris');
      await tester.pump();
      await _tap(tester, extract);
      expect(
        find.textContaining('Extract requested. No data was sent.'),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    },
  );

  testWidgets(
    'Delete removes the requested stable clip and leaves the other audio and notes',
    (tester) async {
      await tester.pumpWidget(_preview(CapturePreviewScenario.populated));
      final original = tester
          .widget<TextField>(find.byType(TextField))
          .controller!
          .text;
      await _tap(tester, find.byTooltip('Delete clip 2'));
      expect(find.text('Clip 2 · 00:16'), findsNothing);
      expect(find.text('Clip 1 · 00:28'), findsOneWidget);
      expect(
        find.textContaining('Clip removed from this preview.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        original,
      );
    },
  );

  testWidgets(
    'valid IME composition commits unchanged text to the caller and enables Extract',
    (tester) async {
      await tester.pumpWidget(_preview(CapturePreviewScenario.empty));
      await tester.showKeyboard(find.byType(TextField));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Mulch',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 0, end: 5),
        ),
      );
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Mulch',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Mulch',
      );
      await _tap(
        tester,
        find.widgetWithText(FilledButton, 'Extract Line Items'),
      );
      expect(
        find.textContaining('Extract requested. No data was sent.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'caller-loaded notes replace editing state without emitting a user edit',
    (tester) async {
      await tester.pumpWidget(_preview(CapturePreviewScenario.populated));
      await _choose(tester, 'Empty');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await _choose(tester, 'Notes only');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        contains('Spread 5 yards'),
      );
      expect(find.textContaining('Edited in this preview.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the notes field preserves accepted Unicode and rejects an edit above 50000 UTF-16 units',
    (tester) async {
      await tester.pumpWidget(_preview(CapturePreviewScenario.empty));
      final field = find.byType(TextField);
      await tester.enterText(field, 'Keep these notes');
      await tester.pump();
      await tester.enterText(field, '${'a' * 49999}e\u0301');
      await tester.pump();
      expect(
        tester.widget<TextField>(field).controller!.text,
        'Keep these notes',
      );
      final exactLimit = '${'a' * 49998}e\u0301';
      await tester.enterText(field, exactLimit);
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, exactLimit);
      expect(find.textContaining('Edited in this preview.'), findsOneWidget);
    },
  );

  testWidgets(
    'unfinished IME composition is not accepted and an over-limit commit restores prior text',
    (tester) async {
      var accepted = 'Keep';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => Column(
                children: [
                  Expanded(
                    child: _screen(
                      CaptureViewData(notes: accepted),
                      onNotesChanged: (value) => update(() => accepted = value),
                    ),
                  ),
                  Text('Accepted units: ${accepted.length}'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.showKeyboard(find.byType(TextField));
      final composing = '${'a' * 49999}e\u0301';
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: composing,
          selection: TextSelection.collapsed(offset: composing.length),
          composing: TextRange(start: 49999, end: composing.length),
        ),
      );
      await tester.pump();
      expect(find.text('Accepted units: 4'), findsOneWidget);
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: composing,
          selection: TextSelection.collapsed(offset: composing.length),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Keep',
      );
      expect(find.text('Accepted units: 4'), findsOneWidget);
    },
  );

  testWidgets(
    'recording displays supplied time and Stop acknowledges without fabricating a clip',
    (tester) async {
      await tester.pumpWidget(_preview(CapturePreviewScenario.recording));
      expect(find.text('Recording · 00:28'), findsOneWidget);
      await _tap(tester, find.byTooltip('Stop recording'));
      expect(
        find.textContaining('Stop requested. This preview recorded no audio.'),
        findsOneWidget,
      );
      expect(find.text('2 clips'), findsOneWidget);
      expect(find.text('Recording · 00:28'), findsNothing);
    },
  );

  testWidgets(
    'five clips prevent Start and deleting one restores the request',
    (tester) async {
      await tester.pumpWidget(_preview(CapturePreviewScenario.clipLimit));
      await tester.ensureVisible(find.text('Maximum 5 clips reached.'));
      expect(_namedIconButton(tester, 'Start recording').onPressed, isNull);
      await _tap(tester, find.byTooltip('Delete clip 5'));
      await _tap(tester, find.byTooltip('Start recording'));
      expect(find.text('Starting recording…'), findsOneWidget);
      expect(find.text('4 clips'), findsOneWidget);
    },
  );

  testWidgets(
    'Extraction busy locks input and failure restores editing with the same content',
    (tester) async {
      await tester.pumpWidget(_preview(CapturePreviewScenario.populated));
      await tester.enterText(find.byType(TextField), 'Keep the gate clear');
      await tester.pump();
      await _tap(
        tester,
        find.widgetWithText(FilledButton, 'Extract Line Items'),
      );
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      expect(_namedIconButton(tester, 'Delete clip 1').onPressed, isNull);
      expect(_namedIconButton(tester, 'Start recording').onPressed, isNull);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Start a blank document'),
            )
            .onPressed,
        isNull,
      );
      await _choose(tester, 'Extraction error');
      expect(
        tester.widget<TextField>(find.byType(TextField)).readOnly,
        isFalse,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Keep the gate clear',
      );
      expect(find.text('2 clips'), findsOneWidget);
      expect(
        find.textContaining(
          'Extraction failed. Your notes and clips are still here.',
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.byType(TextField),
        'Keep the gate clear. Add side path.',
      );
      await tester.pump();
      expect(find.textContaining('Edited in this preview.'), findsOneWidget);
    },
  );

  for (final (scenario, message) in [
    (CapturePreviewScenario.saving, 'Saving on this device…'),
    (CapturePreviewScenario.saved, 'Saved on this device.'),
    (CapturePreviewScenario.saveError, 'Stima could not save this capture.'),
    (CapturePreviewScenario.microphoneDenied, 'Microphone access denied.'),
    (CapturePreviewScenario.microphoneUnavailable, 'Microphone unavailable.'),
    (
      CapturePreviewScenario.interrupted,
      'Recording stopped when you left the app.',
    ),
  ]) {
    testWidgets(
      '${scenario.label} displays its supplied feedback without a false saved claim',
      (tester) async {
        await tester.pumpWidget(_preview(scenario));
        expect(
          find.descendant(
            of: find.byType(CaptureScreen),
            matching: find.textContaining(message),
          ),
          findsOneWidget,
        );
        if (scenario != CapturePreviewScenario.saved) {
          expect(find.text('Saved on this device.'), findsNothing);
        }
        expect(
          find.textContaining('UI preview · synthetic data'),
          findsOneWidget,
        );
        if (scenario == CapturePreviewScenario.microphoneDenied ||
            scenario == CapturePreviewScenario.microphoneUnavailable) {
          expect(_namedIconButton(tester, 'Start recording').onPressed, isNull);
          expect(
            tester.widget<TextField>(find.byType(TextField)).readOnly,
            isFalse,
          );
        }
      },
    );
  }

  testWidgets(
    'Back and blank requests stay in the preview and theme changes preserve notes',
    (tester) async {
      await tester.pumpWidget(const StimaApp());
      await tester.enterText(
        find.byType(TextField),
        'Preserve my in-memory notes',
      );
      await tester.pump();
      await _tap(tester, find.byTooltip('Go back'));
      expect(
        find.text('Back requested. This preview stays open.'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Start a blank document'));
      expect(
        find.text('Start blank requested. No Quote Draft was created.'),
        findsOneWidget,
      );
      await _tap(tester, find.byTooltip('Switch to light theme'));
      expect(find.byTooltip('Switch to dark theme'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Preserve my in-memory notes',
      );
    },
  );

  for (final (size, keyboard, brightness, platform) in [
    (const Size(360, 800), 0.0, Brightness.dark, TargetPlatform.android),
    (const Size(390, 844), 0.0, Brightness.light, TargetPlatform.iOS),
    (const Size(800, 360), 0.0, Brightness.dark, TargetPlatform.iOS),
    (const Size(360, 800), 300.0, Brightness.light, TargetPlatform.android),
  ]) {
    testWidgets(
      'long content remains scrollable at $size, keyboard $keyboard, $brightness, $platform',
      (tester) async {
        _viewport(tester, size, keyboard: keyboard);
        await tester.pumpWidget(
          MaterialApp(
            theme: stimaTheme(brightness).copyWith(platform: platform),
            home: Scaffold(
              body: SafeArea(
                child: _screen(
                  CaptureViewData(
                    notes:
                        'Long field notes about the north boundary and access.\n' *
                        100,
                    clips: [
                      ..._clips,
                      ...List.generate(
                        3,
                        (index) => CaptureClip(
                          id: 'extra-$index',
                          number: index + 3,
                          duration: const Duration(seconds: 12),
                        ),
                      ),
                    ],
                    notice: CaptureNotice(
                      'Connection unavailable. Keep your notes while reviewing the details. ' *
                          8,
                      tone: CaptureNoticeTone.error,
                    ),
                    canExtract: true,
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byType(TextField));
        expect(find.byType(TextField).hitTestable(), findsOneWidget);
        await tester.ensureVisible(find.text('Extract Line Items'));
        expect(find.text('Extract Line Items').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
