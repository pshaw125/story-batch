import { ImageJob } from './planning';
export type JobStatus = 'queued' | 'running' | 'completed' | 'cancelled' | 'failed' | 'unknown';
export interface Capabilities {
  backend: 'fake' | 'draw-things' | 'comfyui'; textToImage: boolean; imageToImage: boolean; loras: boolean;
  cancellation: boolean; progress: boolean; nativeControls: readonly string[];
}
export interface NativeObservations { reportedSamplingSteps?: number; reportedGenerationMs?: number; frameworkJobId?: string }
export interface RenderResult { observations?: NativeObservations; jobId: string; bytes: Uint8Array; mediaType: 'image/png'; cached: boolean; effectiveJob: ImageJob; elapsedMs: number }
export type RenderEvent = { jobId: string; type: 'status'; status: JobStatus } | { jobId: string; type: 'progress'; completed: number; total: number };
export class RenderError extends Error {
  constructor(message: string, public readonly kind: 'validation' | 'render' | 'cancelled' | 'uncertain') { super(message); }
}
/** submit is idempotent by frozen job ID + attempt within the adapter session.
 * Attempt 2 is permitted only after a confirmed render failure; never for a validation
 * failure, cancelled job or unknown/uncertain state. It reuses the exact ImageJob. After uncertain
 * transport outcomes, query status/result before deciding whether a retry is safe.
 * No adapter owns the application queue. No callback may reroll an ImageJob. */
export interface Submission { attempt: 1 | 2 }
export interface Renderer {
  readonly capabilities: Capabilities;
  validate(job: ImageJob): Promise<void>;
  submit(job: ImageJob, onEvent: (event: RenderEvent) => void, submission?: Submission): Promise<string>;
  failure?(handle: string): Promise<RenderError | null>;
  status(handle: string): Promise<JobStatus>;
  result(handle: string): Promise<RenderResult | null>;
  cancel(handle: string): Promise<void>;
}
