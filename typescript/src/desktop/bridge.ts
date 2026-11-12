import type { ImageJob } from '../core/planning';
export interface DesktopBridge {
  preview(source: string): Promise<readonly ImageJob[]>;
  runFake(source: string): Promise<string>;
  cancelFake(): Promise<void>;
  probe(): Promise<{ ok: boolean; checks: object }>;
}
declare global { interface Window { storyBatch: DesktopBridge } }
