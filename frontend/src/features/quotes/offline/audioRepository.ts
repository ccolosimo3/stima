/** Persist audio bytes in IndexedDB and expose metadata separately.
 * An explicit owned deletion commits audio and Capture membership together;
 * aborted writes retain both so the user can retry without a missing reference.
 */
import { CAPTURE_STORE_NAMES, getDb } from "@/features/quotes/offline/captureDb";
import type { LocalAudioClip, LocalAudioClipMeta } from "@/features/quotes/offline/captureTypes";
import { parseStoredCapture } from "@/features/quotes/offline/captureRepositoryShared";
import { dispatchLocalRecoveryChanged } from "@/features/quotes/offline/localRecoveryEvents";

type UnknownRecord = Record<string, unknown>;

type SaveAudioClipInput = Omit<LocalAudioClip, "createdAt">;

/** Insert a recording once; an existing clip identity must never replace saved audio. */
export async function saveAudioClip(clip: SaveAudioClipInput): Promise<void> {
  const blobData = await readBlobAsArrayBuffer(clip.blob);
  const db = await getDb();
  const transaction = db.transaction(CAPTURE_STORE_NAMES.audioClips, "readwrite");
  const store = transaction.objectStore(CAPTURE_STORE_NAMES.audioClips);
  store.add({
    clipId: clip.clipId,
    sessionId: clip.sessionId,
    userId: clip.userId,
    blobData,
    mimeType: clip.mimeType,
    sizeBytes: clip.sizeBytes,
    durationSeconds: clip.durationSeconds,
    sequenceNumber: clip.sequenceNumber,
    createdAt: new Date().toISOString(),
  });
  await transactionDone(transaction);
}

export async function getAudioClip(clipId: string): Promise<LocalAudioClip | null> {
  const db = await getDb();
  const transaction = db.transaction(CAPTURE_STORE_NAMES.audioClips, "readonly");
  const store = transaction.objectStore(CAPTURE_STORE_NAMES.audioClips);
  const rawRecord = await requestToPromise(store.get(clipId));
  await transactionDone(transaction);
  return parseStoredAudioClip(rawRecord);
}

export async function listClipsForSession(sessionId: string): Promise<LocalAudioClipMeta[]> {
  const db = await getDb();
  const transaction = db.transaction(CAPTURE_STORE_NAMES.audioClips, "readonly");
  const store = transaction.objectStore(CAPTURE_STORE_NAMES.audioClips);
  const sessionIndex = store.index("sessionId");
  const rawRecords = await requestToPromise(sessionIndex.getAll(IDBKeyRange.only(sessionId)));
  await transactionDone(transaction);

  return rawRecords
    .map(parseStoredAudioClip)
    .filter((clip): clip is LocalAudioClip => clip !== null && clip.sessionId === sessionId)
    .sort((left, right) => {
      const sequenceDifference = left.sequenceNumber - right.sequenceNumber;
      if (sequenceDifference !== 0) {
        return sequenceDifference;
      }
      return left.createdAt.localeCompare(right.createdAt);
    })
    .map((clip) => {
      const clipMeta = { ...clip };
      Reflect.deleteProperty(clipMeta, "blob");
      return clipMeta as LocalAudioClipMeta;
    });
}

export async function deleteAudioClip(clipId: string): Promise<void> {
  const db = await getDb();
  const transaction = db.transaction(CAPTURE_STORE_NAMES.audioClips, "readwrite");
  const store = transaction.objectStore(CAPTURE_STORE_NAMES.audioClips);
  store.delete(clipId);
  await transactionDone(transaction);
}

/** Delete available owned audio and its intended Capture membership atomically. */
export async function deleteOwnedAudioClip(owner: {
  clipId: string; sessionId: string; userId: string;
}): Promise<void> {
  const db = await getDb();
  const transaction = db.transaction([
    CAPTURE_STORE_NAMES.audioClips, CAPTURE_STORE_NAMES.captureSessions,
  ], "readwrite");
  const done = transactionDone(transaction);
  try {
    const audioStore = transaction.objectStore(CAPTURE_STORE_NAMES.audioClips);
    const sessionStore = transaction.objectStore(CAPTURE_STORE_NAMES.captureSessions);
    const [rawClip, rawSession] = await Promise.all([
      requestToPromise(audioStore.get(owner.clipId)), requestToPromise(sessionStore.get(owner.sessionId)),
    ]);
    const clip = parseStoredAudioClip(rawClip);
    const session = parseStoredCapture(rawSession);
    if (!clip || clip.sessionId !== owner.sessionId || clip.userId !== owner.userId
      || !session || session.userId !== owner.userId) {
      throw new Error("Cannot delete audio that is unavailable or belongs to another Capture.");
    }
    session.clipIds = session.clipIds.filter((id) => id !== owner.clipId);
    session.updatedAt = new Date().toISOString();
    sessionStore.put(session);
    audioStore.delete(owner.clipId);
    await done;
  } catch (error) {
    // A failed request or synchronous put must roll back both stores and settle abort.
    try { transaction.abort(); } catch { /* The transaction may already have aborted. */ }
    await done.catch(() => {});
    throw error;
  }
  dispatchLocalRecoveryChanged({ userId: owner.userId, sessionId: owner.sessionId, reason: "capture_saved" });
}

export async function deleteAllClipsForSession(sessionId: string): Promise<void> {
  const db = await getDb();
  const transaction = db.transaction(CAPTURE_STORE_NAMES.audioClips, "readwrite");
  const store = transaction.objectStore(CAPTURE_STORE_NAMES.audioClips);
  const sessionIndex = store.index("sessionId");
  const clipIds = await requestToPromise(sessionIndex.getAllKeys(IDBKeyRange.only(sessionId)));

  for (const clipId of clipIds) {
    store.delete(clipId);
  }

  await transactionDone(transaction);
}

export async function getTotalAudioBytes(userId: string): Promise<number> {
  const db = await getDb();
  const transaction = db.transaction(CAPTURE_STORE_NAMES.audioClips, "readonly");
  const store = transaction.objectStore(CAPTURE_STORE_NAMES.audioClips);
  const userIndex = store.index("userId");
  const rawRecords = await requestToPromise(userIndex.getAll(IDBKeyRange.only(userId)));
  await transactionDone(transaction);

  return rawRecords
    .map(parseStoredAudioClip)
    .filter((clip): clip is LocalAudioClip => clip !== null && clip.userId === userId)
    .reduce((runningTotal, clip) => runningTotal + clip.sizeBytes, 0);
}

function parseStoredAudioClip(value: unknown): LocalAudioClip | null {
  if (!isRecord(value)) {
    return null;
  }

  const {
    clipId,
    sessionId,
    userId,
    mimeType,
    sizeBytes,
    durationSeconds,
    sequenceNumber,
    createdAt,
  } = value;

  if (
    typeof clipId !== "string" ||
    typeof sessionId !== "string" ||
    typeof userId !== "string" ||
    typeof mimeType !== "string" ||
    typeof sizeBytes !== "number" ||
    !Number.isFinite(sizeBytes) ||
    (durationSeconds !== undefined && (typeof durationSeconds !== "number" || !Number.isFinite(durationSeconds))) ||
    typeof sequenceNumber !== "number" ||
    !Number.isFinite(sequenceNumber) ||
    typeof createdAt !== "string"
  ) {
    return null;
  }

  const blob = resolveStoredBlob(value, mimeType);
  if (!blob) {
    return null;
  }

  return {
    clipId,
    sessionId,
    userId,
    blob: blob as Blob,
    mimeType,
    sizeBytes,
    durationSeconds: durationSeconds as number | undefined,
    sequenceNumber,
    createdAt,
  };
}

function resolveStoredBlob(record: UnknownRecord, mimeType: string): Blob | null {
  const inlineBlob = record.blob;
  if (inlineBlob instanceof Blob) {
    return inlineBlob;
  }

  if (
    isRecord(inlineBlob) &&
    typeof inlineBlob.size === "number" &&
    typeof inlineBlob.type === "string" &&
    typeof inlineBlob.arrayBuffer === "function"
  ) {
    return inlineBlob as unknown as Blob;
  }

  const blobData = record.blobData;
  if (blobData instanceof ArrayBuffer) {
    return new Blob([blobData], { type: mimeType });
  }
  if (ArrayBuffer.isView(blobData)) {
    const copiedBytes = new Uint8Array(blobData.byteLength);
    copiedBytes.set(new Uint8Array(blobData.buffer, blobData.byteOffset, blobData.byteLength));
    return new Blob([copiedBytes.buffer], { type: mimeType });
  }
  if (isRecord(blobData) && typeof blobData.byteLength === "number") {
    const sourceBytes = new Uint8Array(blobData as unknown as ArrayBufferLike);
    const copiedBytes = new Uint8Array(sourceBytes.byteLength);
    copiedBytes.set(sourceBytes);
    return new Blob([copiedBytes.buffer], { type: mimeType });
  }

  return null;
}

async function readBlobAsArrayBuffer(blob: Blob): Promise<ArrayBuffer> {
  const blobWithArrayBuffer = blob as Blob & { arrayBuffer?: () => Promise<ArrayBuffer> };
  if (typeof blobWithArrayBuffer.arrayBuffer === "function") {
    return blobWithArrayBuffer.arrayBuffer();
  }

  if (typeof FileReader !== "undefined") {
    return new Promise<ArrayBuffer>((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result as ArrayBuffer);
      reader.onerror = () => reject(reader.error ?? new Error("Failed to read blob data."));
      reader.readAsArrayBuffer(blob);
    });
  }

  if (typeof Response !== "undefined") {
    return new Response(blob).arrayBuffer();
  }

  throw new Error("Unable to read blob data for persistence.");
}

function isRecord(value: unknown): value is UnknownRecord {
  return typeof value === "object" && value !== null;
}


function requestToPromise<T>(request: IDBRequest<T>): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error("IndexedDB request failed."));
  });
}

function transactionDone(transaction: IDBTransaction): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(transaction.error ?? new Error("IndexedDB transaction failed."));
    transaction.onabort = () => reject(transaction.error ?? new Error("IndexedDB transaction aborted."));
  });
}
