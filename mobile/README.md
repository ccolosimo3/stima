# Stima mobile

Development client for Android and iOS. The app opens one current device-local
Capture with typed notes, audio recording, local playback and recovery. Sign-in,
Extraction and document creation are not available yet. The app does not upload
or synchronize Capture data.

## Local Capture

Run the app with the commands below. Written notes autosave to app-private
Application Support storage. **Start recording** requests microphone permission
when needed; **Stop recording** finishes and saves the clip. Each saved clip has
Play/Stop and Delete controls. There are at most five clips, each up to two
minutes. Deleting a clip does not renumber the other clips.

**Saved on this device** follows the local storage acknowledgement. Closing and
reopening restores the same Capture. Locking or leaving the app stops recording
safely rather than recording in the background; it does not resume automatically.
An unfinished clip stays separately labeled until it can be finalized and saved.
**Retry** checks retained audio or retries the failed save/delete. A failed
playback does not remove the clip. Microphone denial leaves typed notes usable.

Do not treat pending/error feedback as a saved acknowledgement. Latest unsaved
notes remain in memory, but may be lost if the process is killed before a save
succeeds. An incomplete native audio container may be unrecoverable; available
bytes stay owned until explicit deletion. Device storage loss or uninstall can
remove local data. OS/device backup policy is separate from app upload or sync.

The theme control switches dark/light for this run only; dark is the initial
appearance. Exact brand fonts and stored theme preferences are not bundled yet.
Synthetic preview scenarios remain under `test/support/` for presentation tests;
they are not part of the running app and do not prove native operations.

`CaptureScreen` receives `CaptureViewData` and callbacks. The caller owns all
operational state; the screen owns only native text editing. The page's single
lifecycle observer flushes visible composition through that editing owner before
forwarding the exact lifecycle state to the controller. The notes ceiling
matches the web's 50,000 UTF-16 code units. IME composition can finish before an
over-limit committed edit is rejected; only accepted committed text reaches the
caller. No Unicode string is truncated to enforce that limit.

Focused presentation tests, from `mobile/`:

```text
flutter test test/features/capture/capture_screen_test.dart
flutter test test/features/capture/local_capture_page_test.dart
```

Widget tests use the real controller and a real temporary file store with a
bounded fake audio seam. They do not prove a codec, physical microphone,
speaker output or native audio-session transitions. Device acceptance must cover
permission grant/denial, record→play→record, lock/app switch, full-file decode,
terminate/reopen and deletion/reopen on the exact candidate.

## Prerequisites

- Flutter **3.47.9**, including Dart **3.13.7**. The exact Flutter pin is
  [.flutter-version](.flutter-version); the verification script checks the running
  SDK. Follow Flutter's [manual installation](https://docs.flutter.dev/install/manual)
  and [Android setup](https://docs.flutter.dev/platform-integration/android/setup).
- Android SDK and a configured Android emulator or development device. Use
  `flutter doctor` to check your local setup. Put the pinned Flutter SDK's `bin`
  directory on PATH before running the Windows script.

## Verify and run

From the repository root on Windows:

```powershell
powershell -NoProfile -File scripts/mobile-verify.ps1
```

The script checks the SDK version, resolves the committed application lockfile,
checks formatting, analyzes, runs widget tests, and builds the Android debug APK.
It identifies each step and stops with a nonzero exit on the first failure. It
does not install the SDK or change PATH.

On other development hosts, use the same pinned SDK and run from `mobile/`,
stopping if any command fails:

```text
flutter --version --machine
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

Check that `frameworkVersion` in the first command matches `.flutter-version`
before continuing. To launch on a configured Android target from `mobile/`:

```text
flutter devices
flutter run -d <android-device-id>
```

The APK is at `build/app/outputs/flutter-apk/app-debug.apk`. The local verification
entrypoint is separate from the existing web/backend checks; hosted mobile CI is
not configured yet.

## Platform identities and iPhone prerequisite

The pinned generator used `--org com.example --project-name stima_mobile` and
retains its development identifiers:

| Target | Generated identifier |
| --- | --- |
| Android application | `com.example.stima_mobile` |
| iOS Runner | `com.example.stimaMobile` |
| iOS RunnerTests | `com.example.stimaMobile.RunnerTests` |

These are placeholders. Choose final store identities and release signing before
distribution. Do not copy Android's underscore-containing identifier into iOS.
Keep signing credentials and machine-local configuration out of source control.

Native iPhone proof requires the authorized macOS/Xcode route and development
signing. A preview or disposable recorder probe does not establish the final
controller/store/page behavior. The delivery lead retains exact-revision device
evidence and remaining checks. Android emulator and iOS simulator observations
do not establish physical Android or iPhone microphone/interruption behavior.
