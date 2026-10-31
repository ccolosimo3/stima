import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stima_mobile/app/stima_app.dart';
import 'package:stima_mobile/features/capture/application/local_capture_controller.dart';
import 'package:stima_mobile/features/capture/data/local_capture_store.dart';

import 'support/local_capture_test_audio.dart';

void main() {
  testWidgets('opens the real local Capture entry on a narrow phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    late Directory directory;
    late LocalCaptureController controller;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('stima-entry-');
      controller = LocalCaptureController(
        store: LocalCaptureStore(directory),
        audio: LocalCaptureTestAudio(),
      );
      await controller.initialize();
    });
    await tester.pumpWidget(
      StimaApp(createCaptureController: () async => controller),
    );
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
      if (!controller.snapshot.busy) break;
    }
    await tester.pumpAndSettle();

    expect(find.text('Stima').hitTestable(), findsOneWidget);
    expect(find.text('Capture Job Notes').hitTestable(), findsOneWidget);
    expect(
      find.textContaining('Device-local Capture.').hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.runAsync(() => controller.close());
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => directory.delete(recursive: true));
  });
}
