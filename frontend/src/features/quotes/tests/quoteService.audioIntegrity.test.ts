// @vitest-environment node
/** Real IDB-to-HTTP multipart proof using Node's consistent web API realm.
 * The JSDOM suite retains response/error coverage; this verifies uploaded bytes.
 */
import "fake-indexeddb/auto";

import { http, HttpResponse } from "msw";
import { afterAll, afterEach, beforeAll, beforeEach, expect, it, vi } from "vitest";

import { saveAudioClip } from "@/features/quotes/offline/audioRepository";
import { getDb, resetCaptureDbForTests } from "@/features/quotes/offline/captureDb";
import { server } from "@/shared/tests/mocks/server";

let quoteService: typeof import("@/features/quotes/services/quoteService").quoteService;
let transport: typeof import("@/shared/lib/http");
beforeAll(async () => {
  vi.stubEnv("VITE_API_URL", "http://stima.test");
  ({ quoteService } = await import("@/features/quotes/services/quoteService"));
  transport = await import("@/shared/lib/http");
});
beforeEach(resetCaptureDbForTests);
afterEach(async () => {
  transport.clearCsrfToken();
  await resetCaptureDbForTests();
});
afterAll(() => vi.unstubAllEnvs());

it("extract reloads owned legacy clips and sends their ordered bytes with CSRF protection", async () => {
  transport.setCsrfToken("integration-csrf-token");
  let capturedCsrfHeader: string | null = null;
  let capturedContentType: string | null = null;
  let capturedClips: string[] = [];
  await saveAudioClip({
    clipId: "clip-0",
    sessionId: "session-1",
    userId: "user-1",
    blob: new Blob(["clip-1"], { type: "audio/webm" }),
    mimeType: "audio/webm",
    sizeBytes: 6,
    durationSeconds: 2,
    sequenceNumber: 1,
  });
  await saveAudioClip({
    clipId: "clip-1",
    sessionId: "session-1",
    userId: "user-1",
    blob: new Blob(["clip-2"], { type: "audio/mp4" }),
    mimeType: "audio/mp4",
    sizeBytes: 6,
    durationSeconds: 3,
    sequenceNumber: 2,
  });
  (await getDb()).close();

  server.use(
    http.post("http://stima.test/api/quotes/extract", async ({ request }) => {
      capturedCsrfHeader = request.headers.get("X-CSRF-Token");
      capturedContentType = request.headers.get("Content-Type");
      const formData = await request.formData();
      capturedClips = await Promise.all(formData.getAll("clips").map((clip) => typeof clip === "string" ? clip : clip.text()));

      return HttpResponse.json({
        quote_id: "quote-2",
        transcript: "combined transcript",
        line_items: [],
        total: null,
      });
    }),
  );

  const result = await quoteService.extract({
    clipIds: ["clip-0", "clip-1"],
    audioOwner: { sessionId: "session-1", userId: "user-1" },
    notes: "  add 10% travel surcharge  ",
    customerId: "cust-9",
  });

  expect(capturedCsrfHeader).toBe("integration-csrf-token");
  expect(capturedContentType).not.toContain("application/json");
  expect(capturedClips).toEqual(["clip-1", "clip-2"]);
  expect(result).toEqual({
    type: "sync",
    quoteId: "quote-2",
    result: {
      transcript: "combined transcript",
      line_items: [],
      total: null,
    },
  });
});

