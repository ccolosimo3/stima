# Stima mobile

Development client for Android and iOS. The app opens a clearly labeled synthetic
Capture preview using the real presentation widgets. Recording, accounts, storage,
and API access remain later work.

## Capture UI preview

Run the app with the commands below. The top **Preview state** control loads
empty/notes/clips, starting/recording, local-save feedback, microphone/interruption,
and Extraction states. The theme control switches dark/light for this run only;
dark is the initial appearance. Exact brand fonts and stored theme preferences
are not bundled yet.

Notes and clip deletion change in-memory fixture data. Start/Stop, Back, Start
blank and Extract display request feedback; they do not use a microphone, save
files, create documents, navigate to unbuilt screens or contact a server. Extract
locks the supplied input; selecting **Extraction error** keeps the same notes and
clips and restores editing. The interruption state reflects the first-version
stop-and-preserve direction without claiming that this preview saved audio.

`CaptureScreen` receives `CaptureViewData` and callbacks. The caller owns all
operational state; the screen owns only native text editing. The notes ceiling
matches the web's 50,000 UTF-16 code units. IME composition can finish before an
over-limit committed edit is rejected; only accepted committed text reaches the
caller. No Unicode string is truncated to enforce that limit.

Focused presentation tests, from `mobile/`:

```text
flutter test test/features/capture/capture_screen_test.dart
```

Widget/platform-override renders do not prove physical Android/iPhone keyboard,
permission, back/edge-swipe, interruption or save/restart behavior. Those checks
remain with functional capture and the iPhone build route described below.

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

`ios/` contains generated source only. It has not been compiled, signed, or run
on an iOS simulator or iPhone by this Windows foundation task. The platform lead
and parent roadmap must obtain an authorized macOS/Xcode build route and
development signing, then run this foundation on the user's iPhone **before
accepting the first native capture journey**. Android emulator proof does not
establish physical Android or iPhone behavior.
