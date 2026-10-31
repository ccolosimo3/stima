/**
 * Record and reload local audio metadata while blobs remain in IndexedDB.
 * Unavailable saved references stay part of the extraction input; hydration is
 * complete only for the current session, so a partial view cannot erase them.
 */
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  deleteAllClipsForSession,
  deleteOwnedAudioClip,
} from "@/features/quotes/offline/audioRepository";
import {
  canUseMediaRecorder,
  CLIP_LENGTH_LIMIT_REACHED_MESSAGE,
  CLIP_LIMIT_REACHED_MESSAGE,
  CLIP_SAVE_FAILURE_MESSAGE,
  EMPTY_CLIP_MESSAGE,
  loadPersistedVoiceClips,
  MAX_VOICE_CLIP_DURATION_SECONDS,
  MAX_VOICE_CLIPS_PER_CAPTURE,
  persistRecordedClip,
  resolvePreferredMimeType,
  STORAGE_SOFT_CAP_MESSAGE,
  stopStream,
} from "@/features/quotes/hooks/useVoiceCapture.helpers";
import type { UseVoiceCaptureResult, VoiceClip } from "@/features/quotes/hooks/useVoiceCapture.helpers";
import { perfMark, perfMeasure } from "@/shared/perf";
export {
  MAX_VOICE_CLIP_DURATION_SECONDS,
  MAX_VOICE_CLIPS_PER_CAPTURE,
} from "@/features/quotes/hooks/useVoiceCapture.helpers";
export type { VoiceClip } from "@/features/quotes/hooks/useVoiceCapture.helpers";
/** Own recording/storage side effects and preserve unresolved references on resume. */
export function useVoiceCapture(
  sessionId: string | null,
  userId: string | undefined,
): UseVoiceCaptureResult {
  const [clips, setClips] = useState<VoiceClip[]>([]);
  const [unresolvedClipIds, setUnresolvedClipIds] = useState<string[]>([]);
  const [hydratedSessionId, setHydratedSessionId] = useState<string | null>(null);
  const clipIds = useMemo(() => [...clips.map((clip) => clip.id), ...unresolvedClipIds], [clips, unresolvedClipIds]);
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [isRecording, setIsRecording] = useState(false);
  const [isSupported] = useState(canUseMediaRecorder);
  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const startPendingRef = useRef(false);
  const streamRef = useRef<MediaStream | null>(null);
  const timerRef = useRef<number | null>(null);
  const durationLimitRef = useRef<number | null>(null);
  const recordingStartRef = useRef<number | null>(null);
  const chunksRef = useRef<BlobPart[]>([]);
  const clipIdSequenceRef = useRef(0);
  const clipsRef = useRef<VoiceClip[]>([]);
  const sessionIdRef = useRef<string | null>(sessionId);
  const userIdRef = useRef<string | undefined>(userId);
  const recordingSessionIdRef = useRef<string | null>(null);
  const hydrationRef = useRef<{ sessionId: string; promise: Promise<boolean> } | null>(null);
  const hydrateSession = useCallback((targetSessionId: string): Promise<boolean> => {
    if (hydrationRef.current?.sessionId === targetSessionId) return hydrationRef.current.promise;
    // Start and the session effect share readiness, including a newly ensured Capture.
    const promise: Promise<boolean> = loadPersistedVoiceClips(targetSessionId).then((saved) => {
      if (hydrationRef.current?.promise !== promise) return false;
      clipsRef.current = saved.clips;
      setClips(saved.clips);
      setUnresolvedClipIds(saved.unresolvedClipIds);
      setHydratedSessionId(targetSessionId);
      clipIdSequenceRef.current = saved.maxSequence;
      return true;
    }).catch((error) => {
      if (hydrationRef.current?.promise === promise) hydrationRef.current = null;
      throw error;
    });
    hydrationRef.current = { sessionId: targetSessionId, promise };
    return promise;
  }, []);
  useEffect(() => {
    clipsRef.current = clips;
  }, [clips]);
  useEffect(() => {
    sessionIdRef.current = sessionId;
  }, [sessionId]);
  useEffect(() => {
    userIdRef.current = userId;
  }, [userId]);
  useEffect(() => {
    if (!sessionId) {
      hydrationRef.current = null;
      setClips([]);
      setUnresolvedClipIds([]);
      setHydratedSessionId(null);
      clipIdSequenceRef.current = 0;
      return;
    }
    void hydrateSession(sessionId).catch(() => {
      if (sessionIdRef.current === sessionId) {
        setError("Unable to load saved clips on this device.");
      }
    });
  }, [hydrateSession, sessionId]);
  const stopTimer = useCallback(() => {
    if (timerRef.current !== null) {
      window.clearInterval(timerRef.current);
      timerRef.current = null;
    }
  }, []);
  const clearDurationLimitTimer = useCallback(() => {
    if (durationLimitRef.current !== null) {
      window.clearTimeout(durationLimitRef.current);
      durationLimitRef.current = null;
    }
  }, []);
  const clearError = useCallback(() => {
    setError(null);
  }, []);
  const removeClip = useCallback((clipId: string) => {
    const sessionId = sessionIdRef.current;
    const userId = userIdRef.current;
    if (!sessionId || !userId) return;
    void deleteOwnedAudioClip({ clipId, sessionId, userId }).then(() => {
      // Keep the retry control until audio and membership have committed together.
      if (sessionIdRef.current === sessionId && userIdRef.current === userId) {
        setClips((currentClips) => currentClips.filter((clip) => clip.id !== clipId));
      }
    }).catch(() => {
      setError("Could not remove this clip from local storage.");
    });
  }, []);
  const clearClips = useCallback(() => {
    setClips([]);
    setUnresolvedClipIds([]);
    const activeSessionId = sessionIdRef.current;
    if (!activeSessionId) {
      return;
    }
    void deleteAllClipsForSession(activeSessionId).catch(() => {
      setError("Could not clear local clips.");
    });
  }, []);
  const stopRecording = useCallback(() => {
    const recorder = mediaRecorderRef.current;
    if (!recorder || recorder.state === "inactive") {
      return;
    }
    recorder.stop();
  }, []);
  const startRecording = useCallback(async (sessionIdOverride?: string | null) => {
    if (!isSupported) {
      setError("Voice capture is not supported in this browser.");
      return;
    }
    if (isRecording) {
      return;
    }
    const activeSessionId = sessionIdOverride ?? sessionIdRef.current;
    const activeUserId = userIdRef.current;
    if (!activeSessionId || !activeUserId) {
      setError(CLIP_SAVE_FAILURE_MESSAGE);
      return;
    }
    try {
      if (!await hydrateSession(activeSessionId) || sessionIdRef.current !== activeSessionId
        || userIdRef.current !== activeUserId) return;
    } catch {
      setError("Unable to load saved clips on this device.");
      return;
    }
    if (clipsRef.current.length >= MAX_VOICE_CLIPS_PER_CAPTURE) {
      setError(CLIP_LIMIT_REACHED_MESSAGE);
      return;
    }
    if (startPendingRef.current || mediaRecorderRef.current) return;
    startPendingRef.current = true;
    perfMark("capture:record:tap");
    setError(null);
    setElapsedSeconds(0);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      streamRef.current = stream;
      perfMark("capture:record:stream_ready");
      const preferredMimeType = resolvePreferredMimeType();
      const recorder = preferredMimeType
        ? new MediaRecorder(stream, { mimeType: preferredMimeType })
        : new MediaRecorder(stream);
      mediaRecorderRef.current = recorder;
      chunksRef.current = [];
      recordingStartRef.current = Date.now();
      recordingSessionIdRef.current = activeSessionId;
      recorder.ondataavailable = (event: BlobEvent) => {
        if (event.data.size > 0) {
          chunksRef.current.push(event.data);
        }
      };
      recorder.onerror = () => {
        setError("Voice recording failed. Please try again.");
      };
      recorder.onstop = () => {
        void (async () => {
          stopTimer();
          clearDurationLimitTimer();
          const chunks = [...chunksRef.current];
          chunksRef.current = [];
          const recordingStart = recordingStartRef.current;
          const durationSeconds = recordingStart
            ? Math.max(1, Math.round((Date.now() - recordingStart) / 1000))
            : 1;
          try {
            if (chunks.length === 0) {
              setError(EMPTY_CLIP_MESSAGE);
              return;
            }
            const blob = new Blob(chunks, { type: recorder.mimeType || "audio/webm" });
            if (blob.size === 0) {
              setError(EMPTY_CLIP_MESSAGE);
              return;
            }
            const targetSessionId = recordingSessionIdRef.current;
            const targetUserId = userIdRef.current;
            if (!targetSessionId || !targetUserId) {
              setError(CLIP_SAVE_FAILURE_MESSAGE);
              return;
            }
            const { clip, nextSequenceNumber, exceededSoftCap } = await persistRecordedClip({
              clipIdSequence: clipIdSequenceRef.current,
              sessionId: targetSessionId,
              userId: targetUserId,
              blob,
              recorderMimeType: recorder.mimeType,
              durationSeconds,
            });
            clipIdSequenceRef.current = nextSequenceNumber;
            setClips((currentClips) => [...currentClips, clip]);
            if (exceededSoftCap) {
              setError(STORAGE_SOFT_CAP_MESSAGE);
            }
          } catch {
            setError(CLIP_SAVE_FAILURE_MESSAGE);
          } finally {
            stopStream(streamRef.current);
            streamRef.current = null;
            mediaRecorderRef.current = null;
            recordingSessionIdRef.current = null;
            recordingStartRef.current = null;
            setElapsedSeconds(0);
            setIsRecording(false);
          }
        })();
      };
      recorder.start();
      perfMark("capture:record:active");
      perfMeasure("capture:record:tap_to_stream_ms", "capture:record:tap", "capture:record:stream_ready");
      perfMeasure("capture:record:tap_to_active_ms", "capture:record:tap", "capture:record:active");
      setIsRecording(true);
      timerRef.current = window.setInterval(() => {
        setElapsedSeconds((currentSeconds) => currentSeconds + 1);
      }, 1000);
      durationLimitRef.current = window.setTimeout(() => {
        setError(CLIP_LENGTH_LIMIT_REACHED_MESSAGE);
        stopRecording();
      }, MAX_VOICE_CLIP_DURATION_SECONDS * 1000);
    } catch {
      stopTimer();
      clearDurationLimitTimer();
      stopStream(streamRef.current);
      streamRef.current = null;
      mediaRecorderRef.current = null;
      recordingSessionIdRef.current = null;
      setIsRecording(false);
      setError("Microphone access was denied or unavailable.");
    } finally {
      startPendingRef.current = false;
    }
  }, [clearDurationLimitTimer, hydrateSession, isRecording, isSupported, stopRecording, stopTimer]);
  useEffect(() => {
    return () => {
      hydrationRef.current = null;
      stopTimer();
      clearDurationLimitTimer();
      stopStream(streamRef.current);
      const recorder = mediaRecorderRef.current;
      if (recorder && recorder.state !== "inactive") {
        recorder.stop();
      }
    };
  }, [clearDurationLimitTimer, stopTimer]);
  return {
    clips,
    clipIds,
    isHydrating: hydratedSessionId !== sessionId,
    elapsedSeconds,
    error,
    isRecording,
    isSupported,
    startRecording,
    stopRecording,
    removeClip,
    clearClips,
    clearError,
  };
}
