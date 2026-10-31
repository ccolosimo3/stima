import "fake-indexeddb/auto";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { persistRecordedClip } from "@/features/quotes/hooks/useVoiceCapture.helpers";
import {
  deleteAllClipsForSession,
  deleteAudioClip,
  deleteOwnedAudioClip,
  getAudioClip,
  getTotalAudioBytes,
  listClipsForSession,
  saveAudioClip,
} from "@/features/quotes/offline/audioRepository";
import { getDb, resetCaptureDbForTests } from "@/features/quotes/offline/captureDb";
import { createCaptureSession, getCaptureSession, updateCaptureField } from "@/features/quotes/offline/captureRepository";

describe("audioRepository", () => {
  beforeEach(async () => {
    await resetCaptureDbForTests();
  });

  afterEach(async () => {
    vi.restoreAllMocks();
    await resetCaptureDbForTests();
  });

  it("rolls back membership and audio if the owned delete transaction aborts after scheduling both writes", async () => {
    const session = await createCaptureSession({ userId: "user-1", notes: "Keep notes" });
    await updateCaptureField(session.sessionId, { clipIds: ["clip-0", "missing-reference"] });
    await saveAudioClip({
      clipId: "clip-0", sessionId: session.sessionId, userId: "user-1",
      blob: new Blob(["original"]), mimeType: "audio/webm", sizeBytes: 8, sequenceNumber: 1,
    });
    const remove = IDBObjectStore.prototype.delete;
    const abort = vi.spyOn(IDBObjectStore.prototype, "delete").mockImplementation(function (this: IDBObjectStore, key) {
      const request = remove.call(this, key);
      this.transaction.abort();
      return request;
    });
    await expect(deleteOwnedAudioClip({ clipId: "clip-0", sessionId: session.sessionId, userId: "user-1" }))
      .rejects.toThrow();
    abort.mockRestore();
    (await getDb()).close();
    expect(await getCaptureSession(session.sessionId)).toMatchObject({ clipIds: ["clip-0", "missing-reference"] });
    const stored = await getAudioClip("clip-0");
    expect(await readBlobText(stored!.blob)).toBe("original");
    await deleteOwnedAudioClip({ clipId: "clip-0", sessionId: session.sessionId, userId: "user-1" });
    (await getDb()).close();
    expect(await getCaptureSession(session.sessionId)).toMatchObject({ clipIds: ["missing-reference"], notes: "Keep notes" });
    expect(await getAudioClip("clip-0")).toBeNull();
  });

  it("retains genuine mismatched references and audio when deletion ownership does not match", async () => {
    const original = await createCaptureSession({ userId: "user-1" });
    const other = await createCaptureSession({ userId: "user-1" });
    await updateCaptureField(original.sessionId, { clipIds: ["clip-0"] });
    await updateCaptureField(other.sessionId, { clipIds: ["clip-0"] });
    await saveAudioClip({
      clipId: "clip-0", sessionId: original.sessionId, userId: "user-1",
      blob: new Blob(["original"]), mimeType: "audio/webm", sizeBytes: 8, sequenceNumber: 1,
    });
    await expect(deleteOwnedAudioClip({ clipId: "clip-0", sessionId: other.sessionId, userId: "user-1" }))
      .rejects.toThrow();
    await expect(deleteOwnedAudioClip({ clipId: "clip-0", sessionId: original.sessionId, userId: "other-user" }))
      .rejects.toThrow();
    (await getDb()).close();
    expect(await getCaptureSession(original.sessionId)).toMatchObject({ clipIds: ["clip-0"] });
    expect(await getCaptureSession(other.sessionId)).toMatchObject({ clipIds: ["clip-0"] });
    expect(await getAudioClip("clip-0")).toMatchObject({ sessionId: original.sessionId, userId: "user-1" });
  });

  it("preserves recorded bytes across captures and a reset sequence after reopening storage", async () => {
    const recordings = [];
    for (const [sessionId, text] of [["session-a", "first"], ["session-b", "second"], ["session-a", "after reset"]]) {
      const { clip } = await persistRecordedClip({
        clipIdSequence: 0,
        sessionId,
        userId: "user-1",
        blob: new Blob([text], { type: "audio/webm" }),
        recorderMimeType: "audio/webm",
        durationSeconds: 3,
      });
      recordings.push({ clip, sessionId, text });
    }
    (await getDb()).close();

    expect(new Set(recordings.map(({ clip }) => clip.id)).size).toBe(3);
    for (const { clip, sessionId, text } of recordings) {
      const stored = await getAudioClip(clip.id);
      if (!stored) throw new Error(`Saved recording ${clip.id} was lost`);
      expect(stored?.sessionId).toBe(sessionId);
      expect(await readBlobText(stored.blob)).toBe(text);
    }
    expect(await listClipsForSession("session-a")).toHaveLength(2);
    expect(await listClipsForSession("session-b")).toHaveLength(1);
  });

  it("rejects a duplicate recording key without changing the original bytes or metadata", async () => {
    const original = {
      clipId: "clip-0",
      sessionId: "session-a",
      userId: "user-1",
      blob: new Blob(["original"], { type: "audio/webm" }),
      mimeType: "audio/webm",
      sizeBytes: 8,
      durationSeconds: 3,
      sequenceNumber: 1,
    };
    await saveAudioClip(original);
    await expect(saveAudioClip({ ...original, sessionId: "session-b", blob: new Blob(["replacement"]) }))
      .rejects.toThrow();
    (await getDb()).close();

    const stored = await getAudioClip("clip-0");
    if (!stored) throw new Error("The original recording was lost after a duplicate insert");
    expect(stored).toMatchObject({ sessionId: "session-a", userId: "user-1", sequenceNumber: 1 });
    expect(await readBlobText(stored.blob)).toBe("original");
  });

  it("round-trips clip blobs with save/get", async () => {
    const blob = new Blob(["clip-a"], { type: "audio/webm" });
    await saveAudioClip({
      clipId: "clip-1",
      sessionId: "session-1",
      userId: "user-1",
      blob,
      mimeType: blob.type,
      sizeBytes: blob.size,
      durationSeconds: 4,
      sequenceNumber: 1,
    });

    const clip = await getAudioClip("clip-1");

    expect(clip).not.toBeNull();
    expect(clip?.clipId).toBe("clip-1");
    expect(clip?.sessionId).toBe("session-1");
    expect(clip?.blob.size).toBe(blob.size);
    expect(clip?.mimeType).toBe("audio/webm");
    expect(clip?.createdAt).toEqual(expect.any(String));
  });

  it("lists metadata for one session only", async () => {
    const firstBlob = new Blob(["a"], { type: "audio/webm" });
    const secondBlob = new Blob(["b"], { type: "audio/mp4" });

    await saveAudioClip({
      clipId: "clip-a",
      sessionId: "session-a",
      userId: "user-1",
      blob: firstBlob,
      mimeType: firstBlob.type,
      sizeBytes: firstBlob.size,
      durationSeconds: 2,
      sequenceNumber: 1,
    });
    await saveAudioClip({
      clipId: "clip-b",
      sessionId: "session-a",
      userId: "user-1",
      blob: secondBlob,
      mimeType: secondBlob.type,
      sizeBytes: secondBlob.size,
      durationSeconds: 3,
      sequenceNumber: 2,
    });
    await saveAudioClip({
      clipId: "clip-other",
      sessionId: "session-b",
      userId: "user-1",
      blob: new Blob(["c"], { type: "audio/webm" }),
      mimeType: "audio/webm",
      sizeBytes: 1,
      durationSeconds: 1,
      sequenceNumber: 1,
    });

    const clips = await listClipsForSession("session-a");

    expect(clips).toHaveLength(2);
    expect(clips[0]).toEqual(
      expect.objectContaining({
        clipId: "clip-a",
        sequenceNumber: 1,
      }),
    );
    expect(clips[1]).toEqual(
      expect.objectContaining({
        clipId: "clip-b",
        sequenceNumber: 2,
      }),
    );
    expect("blob" in clips[0]).toBe(false);
  });

  it("deletes a single clip", async () => {
    await saveAudioClip({
      clipId: "clip-1",
      sessionId: "session-1",
      userId: "user-1",
      blob: new Blob(["clip-a"], { type: "audio/webm" }),
      mimeType: "audio/webm",
      sizeBytes: 6,
      durationSeconds: 3,
      sequenceNumber: 1,
    });

    await deleteAudioClip("clip-1");

    await expect(getAudioClip("clip-1")).resolves.toBeNull();
  });

  it("deletes all clips for a session", async () => {
    await saveAudioClip({
      clipId: "clip-1",
      sessionId: "session-1",
      userId: "user-1",
      blob: new Blob(["clip-a"], { type: "audio/webm" }),
      mimeType: "audio/webm",
      sizeBytes: 6,
      durationSeconds: 3,
      sequenceNumber: 1,
    });
    await saveAudioClip({
      clipId: "clip-2",
      sessionId: "session-1",
      userId: "user-1",
      blob: new Blob(["clip-b"], { type: "audio/webm" }),
      mimeType: "audio/webm",
      sizeBytes: 7,
      durationSeconds: 4,
      sequenceNumber: 2,
    });
    await saveAudioClip({
      clipId: "clip-3",
      sessionId: "session-2",
      userId: "user-1",
      blob: new Blob(["clip-c"], { type: "audio/webm" }),
      mimeType: "audio/webm",
      sizeBytes: 8,
      durationSeconds: 5,
      sequenceNumber: 1,
    });

    await deleteAllClipsForSession("session-1");

    await expect(listClipsForSession("session-1")).resolves.toEqual([]);
    await expect(getAudioClip("clip-3")).resolves.not.toBeNull();
  });

  it("sums total bytes for a user", async () => {
    await saveAudioClip({
      clipId: "clip-1",
      sessionId: "session-1",
      userId: "user-1",
      blob: new Blob(["clip-a"], { type: "audio/webm" }),
      mimeType: "audio/webm",
      sizeBytes: 10,
      durationSeconds: 3,
      sequenceNumber: 1,
    });
    await saveAudioClip({
      clipId: "clip-2",
      sessionId: "session-2",
      userId: "user-1",
      blob: new Blob(["clip-b"], { type: "audio/webm" }),
      mimeType: "audio/webm",
      sizeBytes: 25,
      durationSeconds: 4,
      sequenceNumber: 2,
    });
    await saveAudioClip({
      clipId: "clip-3",
      sessionId: "session-2",
      userId: "user-2",
      blob: new Blob(["clip-c"], { type: "audio/webm" }),
      mimeType: "audio/webm",
      sizeBytes: 99,
      durationSeconds: 5,
      sequenceNumber: 1,
    });

    await expect(getTotalAudioBytes("user-1")).resolves.toBe(35);
  });
});

function readBlobText(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(reader.error);
    reader.readAsText(blob);
  });
}
