import 'package:flutter/material.dart';

import '../features/capture/application/local_capture_controller.dart';
import '../features/capture/presentation/local_capture_page.dart';
import 'theme/stima_theme.dart';

class StimaApp extends StatefulWidget {
  const StimaApp({super.key, this.createCaptureController});

  final Future<LocalCaptureController> Function()? createCaptureController;

  @override
  State<StimaApp> createState() => _StimaAppState();
}

class _StimaAppState extends State<StimaApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stima',
      theme: stimaTheme(Brightness.light),
      darkTheme: stimaTheme(Brightness.dark),
      themeMode: _themeMode,
      home: LocalCapturePage(
        createController: widget.createCaptureController,
        onToggleTheme: () => setState(() {
          _themeMode = _themeMode == ThemeMode.dark
              ? ThemeMode.light
              : ThemeMode.dark;
        }),
      ),
    );
  }
}
