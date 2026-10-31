import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../domain/local_capture.dart';

/// One Capture's metadata and audio membership. Callers serialize mutations.
class LocalCaptureStore {
  LocalCaptureStore(this.directory);

  final Directory directory;
  int _revision = 0;
  String? _captureId;
  static final _id = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  static final _committed = RegExp(r'^capture-([0-9]{20})\.json$');

  static Future<LocalCaptureStore> openAppStore() async {
    final support = await getApplicationSupportDirectory();
    return LocalCaptureStore(Directory('${support.path}/local_capture'));
  }

  Future<void> _ensureDirectory(Directory value) async {
    final type = await FileSystemEntity.type(value.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      await value.create();
    } else if (type != FileSystemEntityType.directory) {
      throw const FormatException(
        'Capture directory is not an owned directory.',
      );
    }
  }

  Future<List<(int, File)>> _snapshots() async {
    await _ensureDirectory(directory);
    final files = <(int, File)>[];
    await for (final entity in directory.list(followLinks: false)) {
      final name = entity.uri.pathSegments.last;
      final match = _committed.firstMatch(name);
      if (match == null) continue;
      if (entity is! File ||
          await FileSystemEntity.type(entity.path, followLinks: false) !=
              FileSystemEntityType.file) {
        throw const FormatException('Invalid committed Capture file.');
      }
      files.add((int.parse(match[1]!), entity));
    }
    files.sort((a, b) => a.$1.compareTo(b.$1));
    return files;
  }

  Future<LocalCapture> load() async {
    final files = await _snapshots();
    if (files.isEmpty) {
      final audio = Directory('${directory.path}/audio');
      if (await FileSystemEntity.type(audio.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        // Missing metadata must not quietly orphan or overwrite existing audio.
        throw const FormatException('Audio exists without committed metadata.');
      }
      _revision = 0;
      _captureId = const Uuid().v4();
      final capture = LocalCapture(id: _captureId!);
      await save(capture);
      return capture;
    }
    final (revision, file) = files.last;
    // Never fall back to an older revision: it could resurrect a deletion.
    final envelope = jsonDecode(await file.readAsString());
    if (envelope is! Map<String, dynamic> ||
        envelope['schema'] != 1 ||
        envelope['revision'] != revision) {
      throw const FormatException('Unsupported Capture metadata.');
    }
    final capture = _decode(envelope['capture']);
    _revision = revision;
    _captureId = capture.id;
    return capture;
  }

  Future<void> save(LocalCapture capture) async {
    _validate(capture);
    if (_captureId != capture.id) {
      throw const FormatException('Capture ownership changed.');
    }
    await _ensureDirectory(directory);
    final next = _revision + 1;
    final stem = 'capture-${next.toString().padLeft(20, '0')}';
    final destination = File('${directory.path}/$stem.json');
    if (await FileSystemEntity.type(destination.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const FileSystemException('Metadata revision already exists.');
    }
    final temporary = File('${directory.path}/$stem-${const Uuid().v4()}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'schema': 1,
        'revision': next,
        'capture': {
          'id': capture.id,
          'notes': capture.notes,
          'nextClipNumber': capture.nextClipNumber,
          'clips': [
            for (final clip in capture.clips)
              {
                'id': clip.id,
                'number': clip.number,
                'state': clip.state.name,
                'durationMs': clip.duration.inMilliseconds,
              },
          ],
        },
      }),
      flush: true,
    );
    await temporary.rename(destination.path);
    _revision = next;
    // Pruning is housekeeping after publication, not part of acknowledgement.
    try {
      final files = await _snapshots();
      for (final (_, file) in files.take(
        files.length > 2 ? files.length - 2 : 0,
      )) {
        await file.delete();
      }
    } on Exception {
      // A retained older snapshot cannot invalidate the new committed state.
    }
  }

  Future<File> audioFile(LocalCapture capture, LocalAudioClip clip) async {
    _validate(capture);
    if (_captureId != capture.id ||
        !capture.clips.any((value) => value.id == clip.id)) {
      throw const FormatException('Clip is not a member of this Capture.');
    }
    final audio = Directory('${directory.path}/audio');
    await _ensureDirectory(audio);
    final owned = Directory('${audio.path}/${capture.id}');
    await _ensureDirectory(owned);
    final file = File('${owned.path}/${clip.fileName}');
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw const FormatException('Clip path is not an owned audio file.');
    }
    return file;
  }

  Future<void> deleteAudio(LocalCapture capture, LocalAudioClip clip) async {
    final file = await audioFile(capture, clip);
    if (await file.exists()) await file.delete();
  }

  LocalCapture _decode(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['id'] is! String ||
        value['notes'] is! String ||
        value['nextClipNumber'] is! int ||
        value['clips'] is! List) {
      throw const FormatException('Invalid Capture metadata.');
    }
    final clips = <LocalAudioClip>[];
    for (final item in value['clips'] as List) {
      if (item is! Map<String, dynamic> ||
          item['id'] is! String ||
          item['number'] is! int ||
          item['durationMs'] is! int ||
          !LocalClipState.values.any((state) => state.name == item['state'])) {
        throw const FormatException('Invalid audio membership.');
      }
      clips.add(
        LocalAudioClip(
          id: item['id'] as String,
          number: item['number'] as int,
          state: LocalClipState.values.byName(item['state'] as String),
          duration: Duration(milliseconds: item['durationMs'] as int),
        ),
      );
    }
    final capture = LocalCapture(
      id: value['id'] as String,
      notes: value['notes'] as String,
      nextClipNumber: value['nextClipNumber'] as int,
      clips: clips,
    );
    _validate(capture);
    return capture;
  }

  void _validate(LocalCapture capture) {
    final ids = <String>{};
    final numbers = <int>{};
    var priorNumber = 0;
    if (!_id.hasMatch(capture.id) ||
        capture.notes.length > captureNotesMaxCodeUnits ||
        capture.clips.length > captureMaxClips ||
        capture.nextClipNumber < 1) {
      throw const FormatException('Invalid Capture values.');
    }
    for (final clip in capture.clips) {
      if (!_id.hasMatch(clip.id) ||
          !ids.add(clip.id) ||
          !numbers.add(clip.number) ||
          clip.number <= priorNumber ||
          clip.number >= capture.nextClipNumber ||
          clip.duration.isNegative ||
          (clip.state == LocalClipState.ready &&
              clip.duration <= Duration.zero)) {
        throw const FormatException('Invalid clip identity or sequence.');
      }
      priorNumber = clip.number;
    }
  }
}
