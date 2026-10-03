import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { test } from 'node:test';

const runner = new URL('../../Talos/Core/SDKRuntime/SDKRunner.mjs', import.meta.url);
const sdk = new URL('../../built-in-actions/node_modules/@thom1606/talos-sdk/dist/index.js', import.meta.url).href;
const node = new URL('../../built-in-actions/node_modules/@thom1606/talos-sdk/dist/node.js', import.meta.url).href;
async function waitUntil(check) {
  for (let i = 0; i < 150; i++) {
    const result = await check();
    if (result) return result;
    await delay(20);
  }
  throw new Error('Runtime condition timed out');
}
async function fixture(t, source) {
  const directory = await mkdtemp(join(tmpdir(), 'talos-runner-test-'));
  const entry = join(directory, 'extension.mjs');
  await writeFile(entry, `import {talos,defineActions} from ${JSON.stringify(sdk)};
    import {runProcess,writeOutput} from ${JSON.stringify(node)};
    import {writeFile} from 'node:fs/promises';
    ${source}
    export function deactivate() {}`);
  const child = spawn(process.execPath, [runner.pathname, entry], { stdio: ['pipe', 'pipe', 'pipe'] });
  const messages = [];
  let buffer = '', stderr = '';
  child.stdout.setEncoding('utf8');
  child.stdout.on('data', chunk => {
    buffer += chunk;
    for (let end; (end = buffer.indexOf('\n')) >= 0;) {
      messages.push(JSON.parse(buffer.slice(0, end)));
      buffer = buffer.slice(end + 1);
    }
  });
  child.stderr.on('data', chunk => { stderr += chunk; });
  const exited = new Promise(resolve => child.once('close', code => resolve(code)));
  const send = value => child.stdin.write(`${JSON.stringify(value)}\n`);
  const message = predicate => waitUntil(() => messages.find(predicate));
  const activate = (action, requestID, config = {}, files = []) => send({ type: 'activate', requestID, context: { action, config, files } });
  t.after(async () => {
    child.stdin.end();
    const forced = setTimeout(() => child.kill('SIGKILL'), 2000);
    await exited;
    clearTimeout(forced);
    await rm(directory, { recursive: true, force: true });
  });
  return { directory, child, send, activate, message, messages, exited, stderr: () => stderr };
}

test('cancelling running and queued actions cleans files, stops children and keeps the queue usable', async t => {
  const f = await fixture(t, `export const activate=defineActions({
    first: async context => {
      await writeOutput(context.files[0], {suffix:'-result',extension:'txt'}, async temporary => {
        await runProcess(process.execPath,['-e',
          "require('node:fs').writeFileSync(process.argv[1],String(process.pid));process.on('SIGTERM',()=>{});setInterval(()=>{},1000)",context.config.marker]);
      });
    },
    queued: context => writeFile(context.config.marker,'should not run'),
    next: () => console.log('next completed'),
  });`);
  const input = join(f.directory, 'input.txt');
  const marker = join(f.directory, 'child.pid');
  const queued = join(f.directory, 'queued');
  await writeFile(input, 'original');
  f.activate('first', 'first', { marker }, [{ path: input, name: 'input.txt', contentType: 'public.text' }]);
  const pid = Number(await waitUntil(async () => readFile(marker, 'utf8').catch(() => false)));
  f.activate('queued', 'queued', { marker: queued });
  f.send({ type: 'cancelActivation', requestID: 'queued' });
  f.send({ type: 'cancelActivation', requestID: 'first' });
  await f.message(m => m.method === 'activationComplete' && m.requestID === 'first');
  const skipped = await f.message(m => m.method === 'activationComplete' && m.requestID === 'queued');
  assert.ok(skipped.parameters.error);
  assert.throws(() => process.kill(pid, 0), { code: 'ESRCH' });
  assert.equal(await readFile(input, 'utf8'), 'original');
  assert.deepEqual((await readdir(f.directory)).sort(), ['child.pid', 'extension.mjs', 'input.txt']);
  f.activate('next', 'next');
  const next = await f.message(m => m.method === 'activationComplete' && m.requestID === 'next');
  assert.equal(next.parameters.error, undefined);
});

test('window requests get their own live scope and closing a window stops its subprocess', async t => {
  const f = await fixture(t, `export const activate=defineActions({
    open: context => talos.openWindow({title:context.config.title,content:'Hello',
      onRequest: async (method,payload,context) => {
        if (method==='echo') return {title:context.config.title,aborted:context.signal.aborted};
        await runProcess(process.execPath,['-e',
          "require('node:fs').writeFileSync(process.argv[1],String(process.pid));setInterval(()=>{},1000)",payload.marker]);
      },
    }),
  });`);
  f.activate('open', 'open-one', { title: 'one' });
  const one = await f.message(m => m.method === 'openWindow' && m.parameters.title === 'one');
  await f.message(m => m.method === 'activationComplete' && m.requestID === 'open-one');
  assert.equal(Object.hasOwn(JSON.parse(one.parameters.contextJSON), 'signal'), false);
  f.activate('open', 'open-two', { title: 'two' });
  const two = await f.message(m => m.method === 'openWindow' && m.parameters.title === 'two');
  await f.message(m => m.method === 'activationComplete' && m.requestID === 'open-two');
  f.send({ type: 'windowRequest', requestID: 'echo-one', windowID: one.parameters.windowID, method: 'echo', payloadJSON: '{}' });
  const echo = await f.message(m => m.method === 'windowReply' && m.requestID === 'echo-one');
  assert.deepEqual(JSON.parse(echo.parameters.resultJSON), { title: 'one', aborted: false });
  const marker = join(f.directory, 'window-child.pid');
  f.send({ type: 'windowRequest', requestID: 'slow-one', windowID: one.parameters.windowID, method: 'slow', payloadJSON: JSON.stringify({ marker }) });
  const pid = Number(await waitUntil(async () => readFile(marker, 'utf8').catch(() => false)));
  f.send({ type: 'windowClosed', windowID: one.parameters.windowID });
  await waitUntil(() => { try { process.kill(pid, 0); return false; } catch { return true; } });
  f.send({ type: 'windowRequest', requestID: 'echo-two', windowID: two.parameters.windowID, method: 'echo', payloadJSON: '{}' });
  const other = await f.message(m => m.method === 'windowReply' && m.requestID === 'echo-two');
  assert.deepEqual(JSON.parse(other.parameters.resultJSON), { title: 'two', aborted: false });
  assert.equal(f.messages.some(m => m.method === 'windowReply' && m.requestID === 'slow-one'), false);
});

test('host EOF releases a waiting model stream instead of retaining its activation', async t => {
  const f = await fixture(t, `export async function activate() {
    for await (const snapshot of talos.appleIntelligence.stream('hello')) console.log(snapshot);
  }`);
  f.activate('stream', 'stream');
  await f.message(m => m.method === 'modelRequest');
  f.child.stdin.end();
  assert.equal(await f.exited, 0);
  assert.equal(f.stderr(), '');
});

test('host EOF rejects a waiting dialog and lets the runner exit', async t => {
  const f = await fixture(t, 'export async function activate() { await confirm("Continue?"); }');
  f.activate('dialog', 'dialog');
  await f.message(m => m.method === 'dialog');
  f.child.stdin.end();
  assert.equal(await f.exited, 0);
  assert.equal(f.stderr(), '');
});
