import { act, renderHook, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
  MAX_VOICE_CLIPS_PER_CAPTURE,
  useVoiceCapture,
} from "@/features/quotes/hooks/useVoiceCapture";
import {
  deleteOwnedAudioClip,
  getTotalAudioBytes,
  listClipsForSession,
  saveAudioClip,
} from "@/features/quotes/offline/audioRepository";

vi.mock("@/features/quotes/offline/audioRepository", () => ({
  saveAudioClip: vi.fn(),
  deleteOwnedAudioClip: vi.fn(),
  deleteAllClipsForSession: vi.fn(),
  getTotalAudioBytes: vi.fn(async () => 0),
  listClipsForSession: vi.fn(async () => []),
}));
vi.mock("@/features/quotes/offline/captureRepository", () => ({
  getCaptureSession: vi.fn(async () => null),
}));

class FakeMediaRecorder {
  static isTypeSupported = vi.fn(() => true);

  public state: "inactive" | "recording" = "inactive";
  public readonly mimeType: string;
  public ondataavailable: ((event: BlobEvent) => void) | null = null;
  public onerror: (() => void) | null = null;
  public onstop: (() => void) | null = null;

  constructor(_stream: MediaStream, options?: MediaRecorderOptions) {
    this.mimeType = options?.mimeType ?? "audio/webm";
  }

  start(): void {
    this.state = "recording";
  }

  stop(): void {
    if (this.state === "inactive") {
      return;
    }

    this.state = "inactive";
    this.ondataavailable?.({
      data: new Blob(["clip-audio"], { type: this.mimeType }),
    } as BlobEvent);
    this.onstop?.();
  }
}

describe("useVoiceCapture", () => {
  const mockedSaveAudioClip = vi.mocked(saveAudioClip);
  const mockedDeleteAudioClip = vi.mocked(deleteOwnedAudioClip);
  const mockedGetTotalAudioBytes = vi.mocked(getTotalAudioBytes);
  const mockedListClipsForSession = vi.mocked(listClipsForSession);
  const stopTrackMock = vi.fn();
  const getUserMediaMock = vi.fn();

  beforeEach(() => {
    mockedSaveAudioClip.mockReset();
    mockedDeleteAudioClip.mockReset();
    mockedGetTotalAudioBytes.mockReset();
    mockedListClipsForSession.mockReset();
    mockedDeleteAudioClip.mockResolvedValue(undefined);
    mockedGetTotalAudioBytes.mockResolvedValue(0);
    mockedListClipsForSession.mockResolvedValue([]);
    stopTrackMock.mockReset();
    getUserMediaMock.mockResolvedValue({
      getTracks: () => [{ stop: stopTrackMock }],
    } as unknown as MediaStream);

    Object.defineProperty(navigator, "mediaDevices", {
      configurable: true,
      writable: true,
      value: {
        getUserMedia: getUserMediaMock,
      },
    });

    Object.defineProperty(globalThis, "MediaRecorder", {
      configurable: true,
      writable: true,
      value: FakeMediaRecorder,
    });
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it("records, persists clip metadata, and keeps blobs out of React state", async () => {
    const { result } = renderHook(() => useVoiceCapture("session-1", "user-1"));

    await act(async () => {
      await result.current.startRecording();
    });

    expect(result.current.isRecording).toBe(true);

    act(() => {
      result.current.stopRecording();
    });

    await waitFor(() => {
      expect(result.current.clips).toHaveLength(1);
    });

    const storedClip = result.current.clips[0];
    expect(storedClip).toEqual(
      expect.objectContaining({
        id: expect.any(String),
        sequenceNumber: 1,
        mimeType: expect.stringContaining("audio/"),
        sizeBytes: expect.any(Number),
      }),
    );
    expect("blob" in storedClip).toBe(false);
    expect(mockedSaveAudioClip).toHaveBeenCalledTimes(1);
    expect(stopTrackMock).toHaveBeenCalledTimes(1);
  });

  it("removes a clip from state and local storage", async () => {
    const { result } = renderHook(() => useVoiceCapture("session-1", "user-1"));

    await act(async () => {
      await result.current.startRecording();
    });
    act(() => {
      result.current.stopRecording();
    });

    await waitFor(() => {
      expect(result.current.clips).toHaveLength(1);
    });

    const clipId = result.current.clips[0]?.id;
    act(() => {
      result.current.removeClip(clipId ?? "");
    });

    await waitFor(() => {
      expect(result.current.clips).toHaveLength(0);
      expect(mockedDeleteAudioClip).toHaveBeenCalledWith({ clipId, sessionId: "session-1", userId: "user-1" });
    });
  });

  it("hydrates persisted clips when session changes", async () => {
    mockedListClipsForSession.mockResolvedValueOnce([
      {
        clipId: "clip-22",
        sessionId: "session-22",
        userId: "user-1",
        mimeType: "audio/webm",
        sizeBytes: 1234,
        durationSeconds: 7,
        sequenceNumber: 3,
        createdAt: "2026-04-24T00:00:00.000Z",
      },
    ]);

    const { result } = renderHook(() => useVoiceCapture("session-22", "user-1"));

    await waitFor(() => {
      expect(result.current.clips).toEqual([
        {
          id: "clip-22",
          durationSeconds: 7,
          sequenceNumber: 3,
          sizeBytes: 1234,
          mimeType: "audio/webm",
        },
      ]);
    });
  });

  it("enforces max clip count before starting a recording", async () => {
    mockedListClipsForSession.mockResolvedValueOnce(
      Array.from({ length: MAX_VOICE_CLIPS_PER_CAPTURE }, (_, index) => ({
        clipId: `clip-${index}`,
        sessionId: "session-1",
        userId: "user-1",
        mimeType: "audio/webm",
        sizeBytes: 100,
        durationSeconds: 3,
        sequenceNumber: index + 1,
        createdAt: `2026-04-24T00:00:0${index}.000Z`,
      })),
    );

    const { result } = renderHook(() => useVoiceCapture("session-1", "user-1"));

    await waitFor(() => {
      expect(result.current.clips).toHaveLength(MAX_VOICE_CLIPS_PER_CAPTURE);
    });

    await act(async () => {
      await result.current.startRecording();
    });

    expect(result.current.error).toBe("Maximum clips reached.");
    expect(getUserMediaMock).not.toHaveBeenCalled();
  });

  it("does not start or replace the next Capture when an earlier pending hydration completes", async () => {
    let release!: () => void;
    const pending = new Promise<void>((resolve) => { release = resolve; });
    mockedListClipsForSession.mockImplementation(async (sessionId) => {
      if (sessionId === "old-session") await pending;
      return [];
    });
    const { result, rerender } = renderHook(({ sessionId }) => useVoiceCapture(sessionId, "user-1"), {
      initialProps: { sessionId: "old-session" },
    });
    let previousStart!: Promise<void>;
    act(() => { previousStart = result.current.startRecording(); });
    rerender({ sessionId: "next-session" });
    await act(async () => { await result.current.startRecording(); });
    await act(async () => { release(); await previousStart; });
    expect(getUserMediaMock).toHaveBeenCalledTimes(1);
    act(() => { result.current.stopRecording(); });
    await waitFor(() => expect(result.current.clips).toHaveLength(1));
    expect(mockedSaveAudioClip).toHaveBeenCalledWith(expect.objectContaining({ sessionId: "next-session" }));
  });

  it("retries failed hydration before opening the microphone", async () => {
    mockedListClipsForSession.mockRejectedValueOnce(new Error("temporary read failure"));
    const { result } = renderHook(() => useVoiceCapture("session-1", "user-1"));
    await waitFor(() => expect(result.current.error).toBe("Unable to load saved clips on this device."));
    expect(getUserMediaMock).not.toHaveBeenCalled();
    await act(async () => { await result.current.startRecording(); });
    expect(result.current.isRecording).toBe(true);
    expect(result.current.error).toBeNull();
  });

  it("auto-stops recording at the 120-second duration cap", async () => {
    vi.useFakeTimers();
    const { result } = renderHook(() => useVoiceCapture("session-1", "user-1"));

    await act(async () => {
      await result.current.startRecording();
    });

    await act(async () => {
      vi.advanceTimersByTime(120_000);
      await Promise.resolve();
      await Promise.resolve();
    });

    expect(result.current.isRecording).toBe(false);
    expect(result.current.clips).toHaveLength(1);
    expect(result.current.error).toBe("Clip length limit reached.");
    vi.useRealTimers();
  });

  it("shows a storage warning when clip persistence fails", async () => {
    mockedSaveAudioClip.mockRejectedValueOnce(new Error("quota exceeded"));

    const { result } = renderHook(() => useVoiceCapture("session-1", "user-1"));

    await act(async () => {
      await result.current.startRecording();
    });
    act(() => {
      result.current.stopRecording();
    });

    await waitFor(() => {
      expect(result.current.error).toBe(
        "Stima could not save this clip. Free up device storage or remove an existing clip, then try again.",
      );
    });
    expect(result.current.clips).toHaveLength(0);
  });
});
