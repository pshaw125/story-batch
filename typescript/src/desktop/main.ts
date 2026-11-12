import { app, BrowserWindow, ipcMain, session } from 'electron';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { randomUUID } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { setTimeout as delay } from 'node:timers/promises';
import { freezeBatch } from '../core/planning';
import { drawThingsPreset } from '../core/recipes';
import { FakeRenderer } from '../core/fake-renderer';
import { ReportStore, BatchReport } from '../node/storage';
import { runContext } from '../node/environment';
import { hostProbe } from '../node/host-probe';
const probeMode = process.argv.includes('--host-probe');
// Separate from Swift's bundle identifier and state directories.
app.setName('Story Batch TypeScript Spike');
const probeDirectory = probeMode ? mkdtempSync(join(tmpdir(), 'story-batch-electron-probe-')) : null;
app.setPath('userData', probeDirectory ?? join(app.getPath('appData'), 'story-batch-typescript-spike'));
app.on('will-quit', () => { if (probeDirectory) rmSync(probeDirectory, { recursive: true, force: true }); });
app.commandLine.appendSwitch('disable-background-networking');
let window: BrowserWindow | null = null;
let preview: { source: string; batch: ReturnType<typeof freezeBatch> } | null = null;
let active: { renderer: FakeRenderer; handle: string | null; cancelled: boolean } | null = null;
const page = pathToFileURL(join(__dirname, 'index.html')).href;
const prepare = (source: unknown) => {
  if (typeof source !== 'string' || source.length > 2_000_000) throw new Error('Invalid source.');
  return freezeBatch(source, drawThingsPreset(), runContext('fake-renderer', '1'), { random: Math.random, id: randomUUID });
};
async function runFake(source: unknown): Promise<string> {
  if (active) throw new Error('A fake batch is already running.');
  const batch = preview && preview.source === source ? preview.batch : prepare(source), renderer = new FakeRenderer();
  preview = null;
  const state = { renderer, handle: null as string | null, cancelled: false }; active = state;
  try {
    const store = await ReportStore.create(join(app.getPath('userData'), 'spike-batches'), batch);
    const report: BatchReport = structuredClone(await store.load());
    for (const [index, job] of batch.jobs.entries()) {
      if (state.cancelled) break;
      const record = report.records[index];
      state.handle = await renderer.submit(job, () => {});
      record.status = 'running'; record.attempts = 1; await store.save(report);
      for (let step = 1; step <= job.steps && !state.cancelled; step++) { await delay(120); if (!state.cancelled) renderer.advance(state.handle, step); }
      record.status = await renderer.status(state.handle);
      const result = await renderer.result(state.handle);
      if (result) { await store.writeOutput(job, result.bytes); record.output = job.filename; record.elapsedMs = result.elapsedMs; }
      await store.save(report); state.handle = null;
    }
    for (const r of report.records) if (r.status === 'queued') r.status = 'cancelled';
    await store.save(report);
    return `Synthetic batch ${state.cancelled ? 'cancelled' : 'completed'}: ${store.folder}`;
  } finally { active = null; }
}
app.whenReady().then(async () => {
  session.defaultSession.setPermissionRequestHandler((_web, _permission, callback) => callback(false));
  session.defaultSession.webRequest.onBeforeRequest((details, callback) => {
    const url = new URL(details.url);
    callback({ cancel: url.protocol !== 'file:' || !details.url.startsWith(pathToFileURL(__dirname + '/').href) });
  });
  window = new BrowserWindow({ width: 1000, height: 760, show: !probeMode, title: 'Story Batch — TypeScript Phase 1',
    webPreferences: { preload: join(__dirname, 'preload.js'), sandbox: true, contextIsolation: true, nodeIntegration: false } });
  window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  window.webContents.on('will-navigate', event => event.preventDefault());
  const handle = (name: string, action: (...args: unknown[]) => unknown) => ipcMain.handle(name, (event, ...args: unknown[]) => {
    if (event.sender !== window?.webContents || event.senderFrame !== window.webContents.mainFrame || event.senderFrame.url !== page) throw new Error('Untrusted IPC sender.');
    return action(...args);
  });
  handle('preview', source => { const batch = prepare(source); preview = { source: source as string, batch }; return batch.jobs.slice(0, 4); });
  handle('run-fake', runFake);
  handle('cancel-fake', async () => { if (active) { active.cancelled = true; if (active.handle) await active.renderer.cancel(active.handle); } });
  handle('host-probe', async () => {
    try {
      const checks = await hostProbe(), result = { ok: true, checks };
      if (probeMode) { const image = await window!.webContents.capturePage(); image.toPNG(); }
      if (probeMode) { console.log(JSON.stringify(result)); setTimeout(() => app.exit(0), 100); }
      return result;
    } catch (error) { if (probeMode) { console.error(error); app.exit(1); } throw error; }
  });
  window.webContents.on('render-process-gone', (_event, detail) => { if (probeMode) { console.error(detail); app.exit(1); } });
  await window.loadFile(join(__dirname, 'index.html'));
  if (probeMode) {
    const result = await window.webContents.executeJavaScript(`(async () => {
      document.querySelector('#preview').click();
      for (let i=0;i<100 && !document.querySelector('#output').textContent.includes('schemaVersion');i++) await new Promise(r=>setTimeout(r,10));
      if (!document.querySelector('#output').textContent.includes('schemaVersion')) throw new Error('DOM preview failed');
      const done = await window.storyBatch.runFake('count=2;steps=1\\nsynthetic');
      if (!done.includes('completed')) throw new Error('Synthetic batch failed');
      const waiting = window.storyBatch.runFake('count=3;steps=100\\nsynthetic cancel');
      await new Promise(r=>setTimeout(r,40)); await window.storyBatch.cancelFake();
      if (!(await waiting).includes('cancelled')) throw new Error('Synthetic cancellation failed');
      return window.storyBatch.probe();
    })()`);
    if (!result?.ok) app.exit(1);
  }
}).catch(error => { console.error(error); app.exit(1); });
if (probeMode) setTimeout(() => { console.error('Host probe timed out.'); app.exit(1); }, 20000).unref();
app.on('window-all-closed', () => app.quit());
app.on('before-quit', () => { if (active) { active.cancelled = true; if (active.handle) void active.renderer.cancel(active.handle); } });
