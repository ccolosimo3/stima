"""Create an isolated, instrumented copy of the resolved record_ios package."""

import hashlib
import json
from pathlib import Path
import shutil
from urllib.parse import unquote, urlparse


mobile = Path(__file__).resolve().parents[2]
config = mobile / '.dart_tool/package_config.json'
packages = json.loads(config.read_text())['packages']
uri = next(p['rootUri'] for p in packages if p['name'] == 'record_ios')
source = Path(unquote(urlparse(uri).path))
relative = Path('ios/record_ios/Sources/record_ios/delegate/RecorderFileDelegate.swift')
original = (source / relative).read_bytes()
assert hashlib.sha256(original).hexdigest() == (
    'c86e4b862b1d58a90dc1cc2559bc4605ba5c05ab3abc8c5d19518d71f0121d73'
), 'Expected the unchanged record_ios 2.1.1 producer'
override = mobile / 'pubspec_overrides.yaml'
assert not override.exists(), 'Preserve any existing override; do not overwrite it'
target = mobile / '.dart_tool/task748/record_ios'
assert not target.exists(), 'Inspect/remove only the previous owned diagnostic copy first'
shutil.copytree(source, target)
text = original.decode().replace('\r\n', '\n')


def replace(before, after):
    global text
    assert text.count(before) == 1, before
    text = text.replace(before, after)


replace('    recorder.prepareToRecord()\n    recorder.record()', '''    let prepared = recorder.prepareToRecord()
    trace("prepared", recorder, extra: ["returned": prepared])
    let started = recorder.record()
    trace("record-returned", recorder, extra: ["returned": started])
    m_queue.asyncAfter(deadline: .now() + 1) { [weak self, weak recorder] in
      guard let recorder else { return }
      self?.trace("one-second-sample", recorder)
    }''')
replace('    // Dispatches to m_queue', '''    trace("did-finish", recorder, extra: ["successfully": flag])
    // Dispatches to m_queue''')
replace('    m_audioRecorder?.stop()', '''    if let recorder = m_audioRecorder {
      trace("before-stop", recorder)
      recorder.stop()
      trace("after-stop", recorder)
      do {
        let audio = try AVAudioFile(forReading: recorder.url)
        trace("native-file-readable", recorder, extra: [
          "frames": audio.length, "sampleRate": audio.fileFormat.sampleRate,
          "channels": audio.fileFormat.channelCount
        ])
      } catch {
        trace("native-file-error", recorder, extra: ["error": String(describing: error)])
      }
    }''')
replace('  private func deleteFile(path: String) throws {', '''  // Task748 only: append private observations alongside the owned clip.
  private func trace(_ stage: String, _ recorder: AVAudioRecorder, extra: [String: Any] = [:]) {
    var values = extra
    values["stage"] = stage
    values["uptime"] = ProcessInfo.processInfo.systemUptime
    values["isRecording"] = recorder.isRecording
    values["currentTime"] = recorder.currentTime
    values["bytes"] = (try? FileManager.default.attributesOfItem(atPath: recorder.url.path)[.size]) ?? -1
    values["sessionSampleRate"] = AVAudioSession.sharedInstance().sampleRate
    values["inputChannels"] = AVAudioSession.sharedInstance().inputNumberOfChannels
    let url = recorder.url.appendingPathExtension("task748.jsonl")
    // Serialize delegate callbacks and explicit teardown writes as well.
    objc_sync_enter(self)
    defer { objc_sync_exit(self) }
    do {
      var data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
      data.append(10)
      if !FileManager.default.fileExists(atPath: url.path) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
      }
      let file = try FileHandle(forWritingTo: url)
      defer { file.closeFile() }
      file.seekToEndOfFile()
      file.write(data)
    } catch {
      NSLog("Task748 diagnostic write failed: %@", String(describing: error))
    }
  }

  private func deleteFile(path: String) throws {''')
(target / relative).write_text(text)
override.write_text('dependency_overrides:\n  record_ios:\n    path: .dart_tool/task748/record_ios\n')
print('Task-local producer instrumentation prepared; pubspec.lock will resolve a path override.')
