# Native audio failure evidence

Observed on 2026-10-31. Work item and fix proposal: [#748](https://github.com/ccolosimo3/stima/issues/748).

Tested application source: `4e3dbe40a0732f174b506265b355719e25d1d52a`, based on
`f998cea2ad594378773db1b68ac1aa769792ef9d`. Flutter 3.47.9, Dart 3.13.7,
record 7.1.2, record_ios 2.1.1, audioplayers 6.8.1. Instrumentation ran in an
isolated copy of the pinned native producer. No audio-session policy was changed.

## iPhone observation

The operator reported no usable recording. The retained native stage files show:

| Boundary | Result |
| --- | --- |
| Native preparation | false; isRecording false; time 0; output 28 bytes |
| Native record call | false; isRecording false; time 0; output 28 bytes |
| Before Stop | isRecording false; time 0; output 28 bytes |
| Completion | unsuccessful |
| After Stop | output 28 bytes; native file open fails |
| Dart inspection after recorder disposal | output already 28 bytes |
| Player source preparation | DarwinAudioError / AVPlayerItem.Status.failed |

The invalid output therefore predates both player inspection and process
termination. No saved playable clip was established. The exact negotiated native
settings dictionary was not captured. The test app was subsequently confirmed
closed. Raw recordings, app data, screenshots with private paths and logs are
retained privately and are not included here.

## Non-microphone encoder observation

Apple's AVAudioFile wrote one second of generated mono PCM using these AAC
settings on the Mac. No microphone or speaker was used.

| Sample rate / requested bitrate | Encode | Metadata and complete decode |
| --- | --- | --- |
| 16 kHz / 64 kbps | Encode-bitrate setup error 560226676 | No valid output |
| 16 kHz / 32 kbps | Succeeds; 16,000 frames | ffprobe and full ffmpeg decode pass |
| 16 kHz / 48 kbps | Succeeds; 16,000 frames | ffprobe and full ffmpeg decode pass |
| 48 kHz / 64 kbps | Succeeds; 48,000 frames | ffprobe and full ffmpeg decode pass |

For 16 kHz mono AAC, AVAudioConverter's general available list includes 64 kbps,
while its applicable list in this experiment stops at 48 kbps. The pinned native
format owner chooses from the general list. Apple distinguishes
[all codec bitrates](https://developer.apple.com/documentation/avfaudio/avaudioconverter/availableencodebitrates)
from [bitrates applicable to current formats/settings](https://developer.apple.com/documentation/avfaudio/avaudioconverter/applicableencodebitrates).

The official package metadata returned record_ios 2.1.1 as latest. Its downloaded
archive matched SHA256
`21d189f49a598af4697dac4cc9e48389ac0a1fb3e916622b5504a58d9b96313e`.
That source still ignores native preparation/recording Boolean results and uses
the general available bitrate list.

## Limits

The file-encoder experiment gives a concrete mechanism consistent with the phone
failure. It does not establish identical device encoder capabilities, complete
native negotiation on the phone, microphone signal, audible playback or physical
lifecycle correctness. No production correction has been verified by this report.
The operator stopped the manual retry approach and selected Explore/spec planning
with agent-run verification. The proposal and remaining approval boundary are
owned by #748.
