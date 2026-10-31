# Disposable native codec probe

This branch is a temporary direct-package experiment, not the Stima local Capture implementation. It retains the accepted project/toolchain and unrelated source only to make a small native source transfer. Main runs the probe instead of the product preview. It has no backend/provider/account operation and is not production recovery code.

Pins: Flutter 3.47.9 / Dart 3.13.7; record 7.1.2, path_provider 2.1.6, audioplayers 6.8.1, uuid 4.6.0; committed lockfile fixes the resolved native packages.

Development app identities are distinct from Stima:

- Android application ID: `dev.stima.probe.capture_codec_probe` (explicit existing MainActivity class).
- iOS bundle: `dev.stima.probe.captureCodecProbe`; tests append `.RunnerTests`.
- No team or signing material is committed. Use the authorized personal development team on the Mac; no company team, store purchase or cloud service.

From `mobile/` using the pinned SDK:

```text
flutter pub get --enforce-lockfile
flutter analyze lib
flutter run -d <device-id>
```

Use synthetic speech/notes only. On first Start grant microphone access. Stop explicitly, or lock/switch apps after recording is acknowledged, then return. The display logs native/lifecycle events, expected path, stop result, byte count and native-player duration. Play saved uses the local file. Reopen metadata reads the saved record again; force-stop/close and reopen the app to inspect the same ID/file. The request is AAC-LC `.m4a`, mono/16kHz/64kbps; inspect actual output metadata because the platform can adjust settings. No background recording mode/service exists.

To validate actual codec rather than only a returned path, play the synthetic recording and inspect/decode the exported app-owned M4A with native audio tools (for example macOS `afinfo` and `afconvert`). Keep recordings and app containers private; do not commit/upload them. Root coordinates any device container extraction and physical test. An Android emulator does not prove physical microphone/audibility or iPhone lifecycle.

The probe only writes its own app's persistent support directory `stima_codec_probe/`, with unique audio paths and small pending/saved metadata. It does not delete audio on failure, call destructive recorder.cancel, or reset data. Its direct JSON write is NOT the production Capture commit/recovery protocol. No claim of process-death reconstruction of an incomplete M4A. Existing product widget fixtures retained elsewhere in the tree do not provide probe/native coverage. No comprehensive tests or product review is claimed for this disposable branch.
