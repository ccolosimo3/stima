import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stima_mobile/app/stima_app.dart';

void main() {
  testWidgets('opens the synthetic Capture preview on a narrow phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const StimaApp());
    await tester.pumpAndSettle();

    expect(find.text('Stima').hitTestable(), findsOneWidget);
    expect(find.text('Capture Job Notes').hitTestable(), findsOneWidget);
    expect(
      find.textContaining('UI preview · synthetic data').hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
