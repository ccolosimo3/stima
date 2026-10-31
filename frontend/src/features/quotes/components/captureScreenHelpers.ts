/** Capture presentation helpers, including scheduled extraction-stage updates.
 * Callers retain timer IDs for cancellation and own mounted-state checks.
 */
export const EXTRACTION_STAGE_DELAY_MS = 2500;
export const EXTRACTION_POLL_INTERVAL_MS = 2000;
export const EXTRACTION_MAX_POLLS = 60;

export function formatElapsed(seconds: number): string {
  const mins = Math.floor(seconds / 60)
    .toString()
    .padStart(2, "0");
  const secs = (seconds % 60).toString().padStart(2, "0");
  return `${mins}:${secs}`;
}

export function getExtractionStages(hasClips: boolean, hasNotes: boolean): string[] {
  if (hasClips && hasNotes) {
    return ["Uploading audio...", "Transcribing audio...", "Extracting line items from audio and notes..."];
  }
  if (hasClips) {
    return ["Uploading audio...", "Transcribing audio...", "Extracting line items..."];
  }
  return ["Analyzing notes...", "Extracting line items..."];
}

/** Start stage updates; the screen cancels the returned timers on completion or exit. */
export function startExtractionStageTimers(
  stages: string[],
  onStage: (stage: string) => void,
  isMounted: () => boolean,
): number[] {
  onStage(stages[0]);
  return stages.slice(1).map((stage, index) => window.setTimeout(() => {
    if (isMounted()) onStage(stage);
  }, EXTRACTION_STAGE_DELAY_MS * (index + 1)));
}

export function getExtractionHelperCopy(hasClips: boolean, hasNotes: boolean): string | null {
  if (hasClips && hasNotes) {
    return "Extraction saves one draft from your recording and notes for manual review.";
  }
  if (hasClips) {
    return "Extraction saves your recording as a draft for manual review.";
  }
  if (hasNotes) {
    return "Extraction saves your notes as a draft for manual review.";
  }
  return null;
}
