import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createServer } from 'node:http';
import { runContext } from './environment';
export async function hostProbe(): Promise<object> {
  const folder = await mkdtemp(join(tmpdir(), 'story-batch-host-'));
  const server = createServer((_req, res) => { res.end('local-api-ok'); });
  try {
    const file = join(folder, 'probe.data'); await writeFile(file, 'filesystem-ok', { flag: 'wx' });
    const filesystem = await readFile(file, 'utf8');
    const { stdout } = await promisify(execFile)(process.execPath, ['-e', 'process.stdout.write("process-ok")'],
      { env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' }, timeout: 10000, windowsHide: true });
    await new Promise<void>((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
    const address = server.address(); if (!address || typeof address === 'string') throw new Error('Missing loopback port.');
    const response = await fetch(`http://127.0.0.1:${address.port}`, { signal: AbortSignal.timeout(5000) });
    const api = await response.text();
    if (filesystem !== 'filesystem-ok' || stdout !== 'process-ok' || api !== 'local-api-ok') throw new Error('Host probe failed.');
    return { context: runContext('electron-host-probe', process.versions.electron ?? 'unknown'), filesystem, process: stdout, loopbackApi: api };
  } finally { server.closeAllConnections(); if (server.listening) await new Promise<void>(resolve => server.close(() => resolve())); await rm(folder, { recursive: true, force: true }); }
}
