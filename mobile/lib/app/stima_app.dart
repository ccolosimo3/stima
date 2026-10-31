import 'package:flutter/material.dart';

import '../features/capture/presentation/capture_preview.dart';
import 'theme/stima_theme.dart';

class StimaApp extends StatefulWidget {
  const StimaApp({super.key});

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
      home: CapturePreview(
        onToggleTheme: () => setState(() {
          _themeMode = _themeMode == ThemeMode.dark
              ? ThemeMode.light
              : ThemeMode.dark;
        }),
      ),
    );
  }
}
