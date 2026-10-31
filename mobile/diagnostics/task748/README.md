# Task 748: iPhone producer diagnosis

Diagnostic branch only, based on `f998cea2ad594378773db1b68ac1aa769792ef9d`.
These changes must not be integrated into the product as a fix.

Hypothesis: the pinned recorder acknowledges Start even when Apple's preparation
or recording call returns false, or recording does not advance. Observe those
returns, `isRecording`, a one-second time sample, pre/post-Stop byte counts and
native file readability before process termination. The real Capture adapter
then records player preparation separately, after its existing recorder disposal.
This distinguishes producer failure from consumer preparation failure without
assuming that removing a MIME override fixes anything.

From `mobile/`, with pinned Flutter 3.47.9 on PATH:

1. `flutter pub get --enforce-lockfile` on the clean baseline.
2. `python3 diagnostics/task748/prepare.py` creates an isolated copy of the
   resolved `record_ios` package under ignored `.dart_tool/task748/`. It checks
   the original native file hash and never edits the global package cache.
3. `flutter pub get --offline` resolves the explicit generated
   `pubspec_overrides.yaml`. Inspect the lockfile diff: only `record_ios` changes
   from hosted 2.1.1 to the task-local path. Keep that generated override and
   lockfile delta local; the script and pinned input identify the transformation.
4. Run formatting, analyzer, tests and the authorized development-signed iPhone
   Release build. Inspect tracked status after every generation/build operation.

The first device attempt is one operator-coordinated three-second synthetic
recording, explicit Stop and playback. Record the exact built source commit.
Export only this owned app's Capture directory privately and validate AAC/M4A
metadata plus full-file decode. On any failure, close only the owned app and
retain files; do not repeat unchanged. No microphone may remain active while
awaiting input. A successful first attempt permits the separately coordinated
safe-stop/background and terminate/reopen identity/hash check.

GO requires actual microphone audio, valid AAC/M4A/full decode, audible playback,
safe stop and reopen evidence. Otherwise return NO-GO or the precise BLOCKED
prerequisite. Build, recording events and nonzero file size alone cannot pass.
Native `.task748.jsonl` and Dart `.task748-dart.jsonl` files beside each clip are
private diagnostic observations, not product metadata or public attachments.
Publish sanitized source identities, stage outcomes and limits on issue #748.
No account, SDK, global-service or audio-session policy changes are included.

After collecting proof, remove only the generated task override/copy and restore
the owned lockfile to the baseline before any production patch is prepared.
Preserve the original probe and real consumer source/evidence identities.
