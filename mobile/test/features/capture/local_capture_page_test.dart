import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stima_mobile/app/stima_app.dart';
import 'package:stima_mobile/features/capture/application/local_capture_controller.dart';
import 'package:stima_mobile/features/capture/application/local_capture_snapshot.dart';
import 'package:stima_mobile/features/capture/data/local_capture_store.dart';
import 'package:stima_mobile/features/capture/domain/local_capture.dart';

import '../../support/local_capture_test_audio.dart';

class _FailingStore extends LocalCaptureStore {
  _FailingStore(super.directory);
  bool failNext = false;

  @override
  Future<void> save(LocalCapture capture) async {
    if (failNext) {
      failNext = false;
      throw const FileSystemException('Injected write failure');
    }
    await super.save(capture);
  }
}

Future<void> _idle(
  WidgetTester tester,
  LocalCaptureController controller,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    if (!controller.snapshot.busy) break;
  }
  expect(controller.snapshot.busy, isFalse);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  late Directory directory;
  late _FailingStore store;
  late LocalCaptureTestAudio audio;
  late LocalCaptureController controller;

  Future<void> mount(WidgetTester tester, {bool openingFails = false}) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('stima-page-');
      store = _FailingStore(directory);
      audio = LocalCaptureTestAudio();
      controller = LocalCaptureController(
        store: store,
        audio: audio,
        notesDebounce: const Duration(days: 1),
      );
      await controller.initialize();
      controller.updateNotes('Keep gate clear');
      await controller.flush();
    });
    var failOpening = openingFails;
    await tester.pumpWidget(
      StimaApp(
        createCaptureController: () async {
          if (failOpening) {
            failOpening = false;
            throw const FileSystemException('Injected open failure');
          }
          return controller;
        },
      ),
    );
    await tester.pump();
    addTearDown(() async {
      var closed = false;
      unawaited(controller.close().then((_) => closed = true));
      for (var attempt = 0; attempt < 100 && !closed; attempt++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(closed, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => directory.delete(recursive: true));
    });
    if (!openingFails) await _idle(tester, controller);
  }

  testWidgets(
    'real entry restores notes, explains local scope, and preserves input across theme changes',
    (tester) async {
      await mount(tester);
      expect(
        find.textContaining('This app does not upload or sync.'),
        findsOneWidget,
      );
      expect(find.text('Extract Line Items'), findsNothing);
      expect(find.text('Start a blank document'), findsNothing);
      expect(find.byTooltip('Preview state'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Keep gate clear',
      );
      await tester.enterText(find.byType(TextField), 'Mulch by the gate');
      await tester.pump();
      expect(find.text('Saving on this device…'), findsOneWidget);
      await _tap(tester, find.byTooltip('Switch to light theme'));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Mulch by the gate',
      );
      await tester.runAsync(() => controller.flush());
      await tester.pump();
      expect(find.text('Saved on this device.'), findsOneWidget);
      expect(
        await tester.runAsync(
          () async => (await LocalCaptureStore(directory).load()).notes,
        ),
        'Mulch by the gate',
      );
    },
  );

  testWidgets(
    'real commands show finalizing before a playable row, playback failure retains it, and failed deletion retries',
    (tester) async {
      await mount(tester);
      await _tap(tester, find.byTooltip('Start recording'));
      await _idle(tester, controller);
      expect(find.text('Recording · 00:00'), findsOneWidget);
      expect(find.byTooltip('Play clip 1'), findsNothing);
      audio.stopGate = Completer<void>();
      await _tap(tester, find.byTooltip('Stop recording'));
      expect(
        controller.snapshot.recordingPhase,
        LocalRecordingPhase.finalizing,
      );
      expect(find.text('Finishing and saving recording…'), findsWidgets);
      expect(find.byTooltip('Play clip 1'), findsNothing);
      audio.stopGate!.complete();
      await _idle(tester, controller);
      final id = controller.snapshot.clips.single.id;
      expect(find.text('Clip 1 · 00:04'), findsOneWidget);
      await _tap(tester, find.byTooltip('Play clip 1'));
      await _idle(tester, controller);
      expect(find.byTooltip('Stop clip 1'), findsOneWidget);
      await _tap(tester, find.byTooltip('Stop clip 1'));
      await _idle(tester, controller);
      audio.failPlay = true;
      await _tap(tester, find.byTooltip('Play clip 1'));
      await _idle(tester, controller);
      expect(
        find.textContaining('This clip could not be played.'),
        findsOneWidget,
      );
      expect(find.text('Clip 1 · 00:04'), findsOneWidget);
      store.failNext = true;
      await _tap(tester, find.byTooltip('Delete clip 1'));
      await _idle(tester, controller);
      expect(controller.snapshot.clips.single.id, id);
      expect(find.text('Clip 1 · Deletion pending'), findsOneWidget);
      expect(find.byTooltip('Play clip 1'), findsNothing);
      await _tap(tester, find.text('Retry'));
      await _idle(tester, controller);
      expect(controller.snapshot.clips, isEmpty);
      expect(find.text('No clips recorded yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'save failure keeps latest notes visible and Retry commits them',
    (tester) async {
      await mount(tester);
      await tester.enterText(
        find.byType(TextField),
        'Keep the newest notes 🧰',
      );
      store.failNext = true;
      await tester.runAsync(() => controller.flush());
      await tester.pump();
      expect(
        find.textContaining('Your latest changes are not saved yet.'),
        findsOneWidget,
      );
      expect(find.text('Saved on this device.'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Keep the newest notes 🧰',
      );
      await _tap(tester, find.text('Retry'));
      await _idle(tester, controller);
      expect(find.text('Saved on this device.'), findsOneWidget);
      expect(
        await tester.runAsync(
          () async => (await LocalCaptureStore(directory).load()).notes,
        ),
        'Keep the newest notes 🧰',
      );
    },
  );

  for (final oversized in [false, true]) {
    testWidgets(
      'suspension commits visible composition through the existing boundary; oversized=$oversized',
      (tester) async {
        await mount(tester);
        await tester.showKeyboard(find.byType(TextField));
        final text = oversized
            ? '${'a' * 49999}e\u0301'
            : 'Mulch 🧰 by the gate';
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
            composing: TextRange(start: 0, end: text.length),
          ),
        );
        await tester.pump();
        expect(controller.snapshot.notes, 'Keep gate clear');
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await _idle(tester, controller);
        final expected = oversized ? 'Keep gate clear' : text;
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          expected,
        );
        expect(controller.snapshot.notes, expected);
        expect(
          await tester.runAsync(
            () async => (await LocalCaptureStore(directory).load()).notes,
          ),
          expected,
        );
        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await _idle(tester, controller);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'storage composition failure is honest and opening Retry restores saved content',
    (tester) async {
      await mount(tester, openingFails: true);
      expect(
        find.textContaining('Device storage could not be opened.'),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      expect(find.text('Saved on this device.'), findsNothing);
      await _tap(tester, find.text('Retry'));
      await _idle(tester, controller);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Keep gate clear',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).readOnly,
        isFalse,
      );
    },
  );
}
