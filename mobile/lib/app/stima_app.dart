import 'package:flutter/material.dart';

class StimaApp extends StatelessWidget {
  const StimaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stima',
      home: Scaffold(
        appBar: AppBar(title: const Text('Stima')),
        body: const SafeArea(child: Center(child: Text('Capture'))),
      ),
    );
  }
}
