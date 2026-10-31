/** Resume through real capture/voice hooks, IndexedDB and the extraction service.
 * Only surrounding identity/draft context and HTTP responses are synthetic.
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
  clearCsrfToken();
  await resetCaptureDbForTests();
});

function renderCapture(sessionId: string, autoExtract = false) {
  return render(
    <MemoryRouter initialEntries={[`/quotes/capture?localSession=${sessionId}${autoExtract ? "&autoExtract=1" : ""}`]}>
      <ToastProvider><CaptureScreen /></ToastProvider>
    </MemoryRouter>,
  );
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
