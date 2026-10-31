import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stima_mobile/features/capture/data/local_capture_store.dart';
import 'package:stima_mobile/features/capture/domain/local_capture.dart';

const clipId = '1d5963f5-d10a-48dd-baf0-63e61f659753';

void main() {
  late Directory directory;
  late LocalCaptureStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('stima-capture-store-');
    store = LocalCaptureStore(directory);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'real save/reload preserves notes, pending file identity and exact bytes',
    () async {
      final initial = await store.load();
      const pending = LocalAudioClip(id: clipId, number: 1);
      final capture = initial.copyWith(
        notes: 'Synthetic job notes 🧰',
        clips: [pending],
        nextClipNumber: 2,
      );
      await store.save(capture);
      final file = await store.audioFile(capture, pending);
      final bytes = List.generate(4096, (index) => index % 251);
      await file.writeAsBytes(bytes, flush: true);
      final reopenedStore = LocalCaptureStore(directory);
      final reopened = await reopenedStore.load();
      expect(reopened.notes, capture.notes);
      expect(reopened.id, initial.id);
      expect(reopened.clips.single.id, clipId);
      expect(reopened.clips.single.state, LocalClipState.pending);
      expect(
        await (await reopenedStore.audioFile(
          reopened,
          reopened.clips.single,
        )).readAsBytes(),
        bytes,
      );

      final ready = reopened.copyWith(
        clips: [
          pending.withState(
            LocalClipState.ready,
            duration: const Duration(seconds: 3),
          ),
        ],
      );
      await reopenedStore.save(ready);
      final third = await LocalCaptureStore(directory).load();
      expect(third.clips.single.duration, const Duration(seconds: 3));
      expect(third.nextClipNumber, 2);
      expect(third.clips.single.number, 1);
    },
  );

  test(
    'unpublished snapshot cannot replace the last acknowledged notes',
    () async {
      final capture = (await store.load()).copyWith(notes: 'saved');
      await store.save(capture);
      await File(
        '${directory.path}/capture-00000000000000000003-interrupted.tmp',
      ).writeAsString('{"notes":"unsaved"}', flush: true);
      expect((await LocalCaptureStore(directory).load()).notes, 'saved');
    },
  );

  test(
    'real write failure leaves prior commit readable and retry publishes once',
    () async {
      final capture = (await store.load()).copyWith(notes: 'previous');
      await store.save(capture);
      final displaced = await directory.rename('${directory.path}-held');
      await File(directory.path).writeAsString('not a directory');
      try {
        await expectLater(
          store.save(capture.copyWith(notes: 'latest')),
          throwsA(isA<FormatException>()),
        );
      } finally {
        await File(directory.path).delete();
        await displaced.rename(directory.path);
      }
      expect((await LocalCaptureStore(directory).load()).notes, 'previous');
      await store.save(capture.copyWith(notes: 'latest'));
      expect((await LocalCaptureStore(directory).load()).notes, 'latest');
    },
  );

  test(
    'deletion intent survives unlink-before-commit; removal never resurrects',
    () async {
      const clip = LocalAudioClip(
        id: clipId,
        number: 1,
        state: LocalClipState.ready,
        duration: Duration(seconds: 2),
      );
      final capture = (await store.load()).copyWith(
        clips: [clip],
        nextClipNumber: 2,
      );
      await store.save(capture);
      final file = await store.audioFile(capture, clip);
      await file.writeAsBytes([1, 4, 8, 16], flush: true);
      final deleting = capture.copyWith(
        clips: [clip.withState(LocalClipState.deleting)],
      );
      await store.save(deleting);
      await store.deleteAudio(deleting, deleting.clips.single);
      final reopenedStore = LocalCaptureStore(directory);
      final reopened = await reopenedStore.load();
      expect(reopened.clips.single.state, LocalClipState.deleting);
      expect(
        await (await reopenedStore.audioFile(
          reopened,
          reopened.clips.single,
        )).exists(),
        false,
      );
      await reopenedStore.deleteAudio(reopened, reopened.clips.single);
      await reopenedStore.save(reopened.copyWith(clips: []));
      expect((await LocalCaptureStore(directory).load()).clips, isEmpty);
      expect((await LocalCaptureStore(directory).load()).nextClipNumber, 2);
    },
  );

  test(
    'corrupt or unsupported newest commit fails closed without resetting',
    () async {
      final capture = (await store.load()).copyWith(notes: 'old notes');
      await store.save(capture);
      final newest = File(
        '${directory.path}/capture-00000000000000000003.json',
      );
      await newest.writeAsString('{broken', flush: true);
      await expectLater(
        LocalCaptureStore(directory).load(),
        throwsFormatException,
      );
      expect(await newest.readAsString(), '{broken');
      await newest.writeAsString(
        jsonEncode({'schema': 99, 'revision': 3, 'capture': {}}),
      );
      await expectLater(
        LocalCaptureStore(directory).load(),
        throwsFormatException,
      );
      expect(jsonDecode(await newest.readAsString())['schema'], 99);
    },
  );

  test('stored traversal, duplicate identity and out-of-order membership are rejected', () async {
    final capture = await store.load();
    final snapshot = File(
      '${directory.path}/capture-00000000000000000001.json',
    );
    final original =
        jsonDecode(await snapshot.readAsString()) as Map<String, dynamic>;
    for (final clips in [
      [
        {'id': '../outside', 'number': 1, 'state': 'pending', 'durationMs': 0},
      ],
      [
        for (var i = 0; i < 2; i++)
          {'id': clipId, 'number': i + 1, 'state': 'pending', 'durationMs': 0},
      ],
      [
        {'id': clipId, 'number': 4, 'state': 'ready', 'durationMs': 1},
      ],
    ]) {
      final invalid = Map<String, dynamic>.from(original);
      invalid['capture'] = {
        'id': capture.id,
        'notes': '',
        'nextClipNumber': 3,
        'clips': clips,
      };
      await snapshot.writeAsString(jsonEncode(invalid));
      await expectLater(
        LocalCaptureStore(directory).load(),
        throwsFormatException,
      );
    }
  });
}
