/** Exercise real Capture/voice hooks, IndexedDB, extraction and outbox owners.
 * Identity/draft context, recorder, HTTP response and adverse storage scheduling
 * are synthetic; persistence and submitted clip membership remain real.
 */
import "fake-indexeddb/auto";

import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { MemoryRouter } from "react-router-dom";
import { afterEach, beforeEach, expect, it, vi } from "vitest";

import { CaptureScreen } from "@/features/quotes/components/CaptureScreen";
import * as audioRepository from "@/features/quotes/offline/audioRepository";
import { getDb, resetCaptureDbForTests } from "@/features/quotes/offline/captureDb";
import { createCaptureSession, getCaptureSession, updateCaptureField } from "@/features/quotes/offline/captureRepository";
import { runOutboxPass } from "@/features/quotes/offline/outboxEngine";
import { getJobForSession } from "@/features/quotes/offline/outboxRepository";
import { clearCsrfToken, setCsrfToken } from "@/shared/lib/http";
import { server } from "@/shared/tests/mocks/server";
import { ToastProvider } from "@/ui/Toast";

vi.mock("@/features/auth/hooks/useAuth", () => ({
  useAuth: () => ({ user: { id: "audio-user" } }),
}));
vi.mock("@/features/quotes/hooks/useQuoteDraft", () => ({
  useQuoteDraft: () => ({ setDraft: vi.fn() }),
}));

beforeEach(async () => {
  await resetCaptureDbForTests();
  setCsrfToken("audio-integrity-csrf");
});

afterEach(async () => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  clearCsrfToken();
  await resetCaptureDbForTests();
});

class SyntheticRecorder {
  static isTypeSupported() { return true; }
  state = "inactive";
  mimeType = "audio/webm";
  ondataavailable: ((event: { data: Blob }) => void) | null = null;
  onstop: (() => void) | null = null;
  start() { this.state = "recording"; }
  stop() {
    this.state = "inactive";
    this.ondataavailable?.({ data: new Blob(["complete spoken requirements"], { type: this.mimeType }) });
    this.onstop?.();
  }
}

function readBlobText(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(reader.error);
    reader.readAsText(blob);
  });
}

function renderCapture(sessionId?: string, autoExtract = false) {
  return render(
    <MemoryRouter initialEntries={[`/quotes/capture${sessionId ? `?localSession=${sessionId}${autoExtract ? "&autoExtract=1" : ""}` : ""}`]}>
      <ToastProvider><CaptureScreen /></ToastProvider>
    </MemoryRouter>,
  );
}

function enableRecorder() {
  vi.stubGlobal("MediaRecorder", SyntheticRecorder);
  vi.stubGlobal("navigator", {
    onLine: true, userAgent: navigator.userAgent,
    mediaDevices: { getUserMedia: vi.fn(async () => ({ getTracks: () => [{ stop() {} }] })) },
  });
}

it("retains unresolved legacy input through pending automatic extraction, autosave and explicit Extract", async () => {
  const session = await createCaptureSession({ userId: "audio-user", notes: "Keep the original requirements" });
  await updateCaptureField(session.sessionId, { clipIds: ["clip-0"] });
  await audioRepository.saveAudioClip({
    clipId: "clip-0", sessionId: "another-capture", userId: "audio-user",
    blob: new Blob(["another job"], { type: "audio/webm" }),
    mimeType: "audio/webm", sizeBytes: 11, durationSeconds: 3, sequenceNumber: 1,
  });
  let releaseAudio!: () => void;
  const pendingAudio = new Promise<void>((resolve) => { releaseAudio = resolve; });
  const readAudio = audioRepository.listClipsForSession;
  const pendingRead = vi.spyOn(audioRepository, "listClipsForSession").mockImplementation(async (sessionId) => {
    await pendingAudio;
    return readAudio(sessionId);
  });
  let extractionRequests = 0;
  server.use(http.post("/api/quotes/extract", () => {
    extractionRequests += 1;
    return HttpResponse.json({ detail: "Unexpected partial submission" }, { status: 503 });
  }));

  const view = renderCapture(session.sessionId, true);
  try {
    await screen.findByDisplayValue("Keep the original requirements");
    await waitFor(() => expect(pendingRead).toHaveBeenCalled());
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 450)); });
    expect(screen.getByRole("button", { name: "Extract Line Items" })).toBeDisabled();
    expect(extractionRequests).toBe(0);
    await act(async () => { releaseAudio(); });
    await screen.findByText(/Audio clip is missing from local storage/);
    await waitFor(() => expect(screen.getByRole("button", { name: "Extract Line Items" })).toBeEnabled());
    fireEvent.click(screen.getByRole("button", { name: "Extract Line Items" }));
    await screen.findByText(/Audio clip is missing from local storage/);
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 450)); });
    view.unmount();
    (await getDb()).close();

    expect(await getCaptureSession(session.sessionId)).toMatchObject({
      notes: "Keep the original requirements", clipIds: ["clip-0"],
    });
    expect(await audioRepository.getAudioClip("clip-0")).toMatchObject({ sessionId: "another-capture" });
    expect(extractionRequests).toBe(0);
  } finally {
    releaseAudio();
    view.unmount();
  }
});

it("persists an explicit available-clip deletion without resurrecting the saved reference", async () => {
  const session = await createCaptureSession({ userId: "audio-user", notes: "Keep these notes" });
  await updateCaptureField(session.sessionId, { clipIds: ["clip-0"] });
  await audioRepository.saveAudioClip({
    clipId: "clip-0", sessionId: session.sessionId, userId: "audio-user",
    blob: new Blob(["owned audio"], { type: "audio/webm" }),
    mimeType: "audio/webm", sizeBytes: 11, durationSeconds: 3, sequenceNumber: 1,
  });
  const view = renderCapture(session.sessionId);
  fireEvent.click(await screen.findByRole("button", { name: "Delete clip 1" }));
  await waitFor(async () => {
    expect(await getCaptureSession(session.sessionId)).toMatchObject({ clipIds: [], notes: "Keep these notes" });
    expect(await audioRepository.getAudioClip("clip-0")).toBeNull();
  });
  view.unmount();
  (await getDb()).close();
  expect(await getCaptureSession(session.sessionId)).toMatchObject({ clipIds: [], notes: "Keep these notes" });
});

it("keeps a first recording complete through pending hydration, foreground extraction and the queued retry", async () => {
  enableRecorder();
  const session = await createCaptureSession({ userId: "audio-user", notes: "Written requirements" });
  const connection = await getDb();
  const readAudio = audioRepository.listClipsForSession;
  let hold = true;
  let lock: IDBTransaction | undefined;
  let entered!: () => void;
  const audioRead = new Promise<void>((resolve) => { entered = resolve; });
  vi.spyOn(audioRepository, "listClipsForSession").mockImplementation(async (id) => {
    // Only the capture store is contended; the real audio store remains writable.
    if (!lock) {
      lock = connection.transaction("capture_sessions", "readwrite");
      const store = lock.objectStore("capture_sessions");
      const keepAlive = () => { store.get(id).onsuccess = () => { if (hold) keepAlive(); }; };
      keepAlive();
    }
    const rows = await readAudio(id);
    entered();
    return rows;
  });
  const submitted: Array<{ clips: string[]; notes: FormDataEntryValue | null; key: string | null }> = [];
  vi.spyOn(globalThis, "fetch").mockImplementation(async (_input, init) => {
    const body = init?.body as FormData;
    submitted.push({
      clips: await Promise.all(body.getAll("clips").map((clip) => readBlobText(clip as Blob))),
      notes: body.get("notes"), key: new Headers(init?.headers).get("Idempotency-Key"),
    });
    return new Response(JSON.stringify({ detail: "Synthetic retryable response" }), {
      status: 503, headers: { "Content-Type": "application/json" },
    });
  });
  const view = renderCapture(session.sessionId);
  try {
    await screen.findByDisplayValue("Written requirements");
    await act(async () => { await audioRead; });
    fireEvent.click(screen.getByRole("button", { name: "Start recording" }));
    fireEvent.click(screen.getByRole("button", { name: "Start recording" }));
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 30)); });
    // Either readiness may defer Start, or a completed recording must survive it.
    const earlyStop = screen.queryByRole("button", { name: "Stop recording" });
    if (earlyStop) {
      fireEvent.click(earlyStop);
      await screen.findByRole("button", { name: "Delete clip 1" });
    }
    await act(async () => {
      hold = false;
      await new Promise<void>((resolve) => { lock!.oncomplete = () => resolve(); });
    });
    if (!earlyStop) fireEvent.click(await screen.findByRole("button", { name: "Stop recording" }));
    await waitFor(() => expect(screen.getByRole("button", { name: "Extract Line Items" })).toBeEnabled());
    fireEvent.click(screen.getByRole("button", { name: "Extract Line Items" }));
    await screen.findByText("Synthetic retryable response");
    expect(await getJobForSession(session.sessionId)).not.toBeNull();
    await act(async () => { await runOutboxPass("audio-user"); });
    expect(submitted).toHaveLength(2);
    expect(submitted.map(({ clips }) => clips)).toEqual([
      ["complete spoken requirements"], ["complete spoken requirements"],
    ]);
    expect(submitted[0].notes).toBe("Written requirements");
    expect(submitted[1].key).toBe(submitted[0].key);
    expect(navigator.mediaDevices.getUserMedia).toHaveBeenCalledTimes(1);
    view.unmount();
    (await getDb()).close();
    const saved = await getCaptureSession(session.sessionId);
    expect(saved?.clipIds).toHaveLength(1);
    expect(await audioRepository.getAudioClip(saved!.clipIds[0])).toMatchObject({ sessionId: session.sessionId });
  } finally {
    hold = false;
    view.unmount();
  }
});

it("starts the first recording with one tap when that tap creates the Capture", async () => {
  enableRecorder();
  const view = renderCapture();
  fireEvent.click(screen.getByRole("button", { name: "Start recording" }));
  fireEvent.click(await screen.findByRole("button", { name: "Stop recording" }));
  await screen.findByRole("button", { name: "Delete clip 1" });
  await waitFor(() => expect(screen.getByRole("button", { name: "Extract Line Items" })).toBeEnabled());
  const transaction = (await getDb()).transaction("capture_sessions", "readonly");
  const sessions = await new Promise<Array<{ sessionId: string; clipIds: string[] }>>((resolve) => {
    const request = transaction.objectStore("capture_sessions").getAll();
    request.onsuccess = () => resolve(request.result);
  });
  view.unmount();
  (await getDb()).close();
  expect(sessions).toHaveLength(1);
  const saved = await getCaptureSession(sessions[0].sessionId);
  expect(saved?.clipIds).toHaveLength(1);
  expect(await audioRepository.getAudioClip(saved!.clipIds[0])).toMatchObject({ sessionId: saved!.sessionId });
});

it("keeps an owned clip and its delete control when membership removal aborts, then deletes durably on retry", async () => {
  const session = await createCaptureSession({ userId: "audio-user", notes: "Keep these notes" });
  await updateCaptureField(session.sessionId, { clipIds: ["clip-0"] });
  await audioRepository.saveAudioClip({
    clipId: "clip-0", sessionId: session.sessionId, userId: "audio-user",
    blob: new Blob(["owned audio"], { type: "audio/webm" }),
    mimeType: "audio/webm", sizeBytes: 11, durationSeconds: 3, sequenceNumber: 1,
  });
  let view = renderCapture(session.sessionId);
  await screen.findByRole("button", { name: "Delete clip 1" });
  await waitFor(() => expect(screen.getByRole("button", { name: "Extract Line Items" })).toBeEnabled());
  await act(async () => { await new Promise((resolve) => setTimeout(resolve, 450)); });
  const put = IDBObjectStore.prototype.put;
  const failedWrite = vi.spyOn(IDBObjectStore.prototype, "put").mockImplementation(function (this: IDBObjectStore, value, ...args) {
    if (this.name === "capture_sessions" && value.sessionId === session.sessionId && value.clipIds.length === 0) {
      failedWrite.mockRestore();
      this.transaction.abort();
      throw new DOMException("Synthetic membership write failure", "QuotaExceededError");
    }
    return put.call(this, value, ...args);
  });
  fireEvent.click(screen.getByRole("button", { name: "Delete clip 1" }));
  await screen.findByText("Could not remove this clip from local storage.");
  expect(screen.getByRole("button", { name: "Delete clip 1" })).toBeEnabled();
  view.unmount();
  (await getDb()).close();
  expect(await getCaptureSession(session.sessionId)).toMatchObject({ clipIds: ["clip-0"] });
  expect(await audioRepository.getAudioClip("clip-0")).not.toBeNull();
  view = renderCapture(session.sessionId);
  fireEvent.click(await screen.findByRole("button", { name: "Delete clip 1" }));
  await waitFor(() => expect(screen.queryByRole("button", { name: "Delete clip 1" })).not.toBeInTheDocument());
  view.unmount();
  (await getDb()).close();
  expect(await getCaptureSession(session.sessionId)).toMatchObject({ clipIds: [], notes: "Keep these notes" });
  expect(await audioRepository.getAudioClip("clip-0")).toBeNull();
});
