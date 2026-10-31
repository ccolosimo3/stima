import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

void main() => runApp(const MaterialApp(home: CodecProbe()));

class CodecProbe extends StatefulWidget {
  const CodecProbe({super.key});
  @override
  State<CodecProbe> createState() => _CodecProbeState();
}

class _CodecProbeState extends State<CodecProbe> with WidgetsBindingObserver {
  final _player = AudioPlayer();
  final _events = <String>[];
  late final _root = getApplicationSupportDirectory().then(
    (base) =>
        Directory('${base.path}/stima_codec_probe').create(recursive: true),
  );
  AudioRecorder? _recorder;
  StreamSubscription<RecordState>? _subscription;
  Future<void>? _finishing;
  String? _pending;
  String? _saved;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  void _log(String text) {
    debugPrint('CODEC_PROBE $text');
    if (mounted) setState(() => _events.add(text));
  }

  String _clipPath(Directory root, String id) {
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(id)) {
      throw const FormatException('Unexpected probe identity');
    }
    return '${root.path}/$id.m4a';
  }

  Future<void> _load() async {
    try {
      final root = await _root;
      for (final name in ['saved', 'pending']) {
        final manifest = File('${root.path}/$name.json');
        if (await manifest.exists()) {
          final data = jsonDecode(await manifest.readAsString()) as Map;
          final path = _clipPath(root, data['id'] as String);
          if (name == 'saved') _saved = data['id'] as String;
          if (name == 'pending') _pending = data['id'] as String;
          _log(
            'Reopened $name ${data['id']} bytes=${await File(path).length()}',
          );
        }
      }
    } catch (error) {
      _log('Load error (no reset): $error');
    }
  }

  Future<void> _start() async {
    if (_recorder != null || _pending != null) return;
    final recorder = AudioRecorder();
    _recorder = recorder;
    try {
      if (!await recorder.hasPermission()) {
        _log('Permission denied');
        _recorder = null;
        await recorder.dispose();
        return;
      }
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        _log('Permission completed offscreen; start refused');
        _recorder = null;
        await recorder.dispose();
        return;
      }
      final root = await _root;
      final id = const Uuid().v4();
      final path = _clipPath(root, id);
      if (await File(path).exists()) throw StateError('Refuse overwrite');
      await _player.stop();
      await File('${root.path}/pending.json')
          .writeAsString(jsonEncode({'id': id}), flush: true);
      _pending = id;
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        _log('Left app before native start; reserved path retained');
        return;
      }
      _subscription = recorder.onStateChanged().listen(
        (state) {
          _log('Native state ${state.name}');
          if (identical(_recorder, recorder) &&
              (state == RecordState.pause || state == RecordState.stop)) {
            unawaited(_finish());
          }
        },
        onError: (Object error) {
          _log('Native error: $error; bytes retained');
          unawaited(_finish());
        },
      );
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          bitRate: 64000,
          numChannels: 1,
          audioInterruption: AudioInterruptionMode.pause,
        ),
        path: path,
      );
      _log('Start acknowledged $id');
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        await _finish();
      }
    } catch (error) {
      _log('Start error, no discard: $error');
    }
  }

  Future<void> _finish() => _finishing ??= _finalize().whenComplete(() {
    _finishing = null;
  });

  Future<void> _finalize() async {
    final id = _pending;
    if (id == null) return;
    try {
      final path = _clipPath(await _root, id);
      final reported = await _recorder?.stop();
      _log('Stop returned ${reported ?? 'null'}; expected path retained');
      final bytes = await File(path).length();
      if (bytes == 0) throw StateError('Empty output');
      await _player.setSourceDeviceFile(path, mimeType: 'audio/mp4');
      final duration = await _player.getDuration();
      if (duration == null || duration <= Duration.zero) {
        throw StateError('No positive native-player duration');
      }
      final root = await _root;
      final manifest = File('${root.path}/saved.json');
      await manifest.writeAsString(
        jsonEncode({
          'id': id,
          'bytes': bytes,
          'milliseconds': duration.inMilliseconds,
        }),
        flush: true,
      );
      final reread = jsonDecode(await manifest.readAsString()) as Map;
      if (reread['id'] != id) throw StateError('Reload mismatch');
      await File('${root.path}/pending.json').delete();
      _saved = id;
      _pending = null;
      await _subscription?.cancel();
      await _recorder?.dispose();
      _recorder = null;
      _log('Prepared/saved/reloaded $id bytes=$bytes duration=$duration');
    } catch (error) {
      _log('Finalize error, expected file retained for retry: $error');
    }
  }

  Future<void> _play() async {
    final id = _saved;
    if (id == null || _pending != null) return;
    await _player.play(
      DeviceFileSource(_clipPath(await _root, id), mimeType: 'audio/mp4'),
    );
    _log('Playback requested for $id');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _log('Lifecycle ${state.name}');
    if (state != AppLifecycleState.resumed) {
      unawaited(_player.stop());
      if (_pending != null) unawaited(_finish());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    unawaited(_recorder?.dispose());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Disposable codec probe')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Synthetic inputs only. Direct plugin/file probe; not Stima recovery.',
          ),
          FilledButton(
            onPressed: _recorder == null && _pending == null ? _start : null,
            child: const Text('Start recording'),
          ),
          FilledButton(
            onPressed: _pending != null ? _finish : null,
            child: const Text('Stop / retry finalize'),
          ),
          OutlinedButton(
            onPressed: _saved != null && _pending == null ? _play : null,
            child: const Text('Play saved'),
          ),
          OutlinedButton(
            onPressed: _load,
            child: const Text('Reopen metadata'),
          ),
          SelectableText(_events.join('\n')),
        ],
      ),
    ),
  );
}
