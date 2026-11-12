import { arch, release, type } from 'node:os';
import { randomUUID } from 'node:crypto';
import { RunContext } from '../core/planning';
export function runContext(framework: string, version: string): RunContext {
  return { id: randomUUID(), createdAt: new Date().toISOString(), os: { name: type(), version: release(), arch: arch() },
    framework: { name: framework, version }, hardware: 'unknown', driver: 'unknown', computeRuntime: 'unknown', applicationVersion: '0.1.0' };
}
