import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readFile, rm, mkdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { randomUUID } from 'node:crypto';
import { settings, localize } from '../sdk/src/index.mjs';
import { outputFile } from '../built-in-actions/src/files.mjs';
const execute = promisify(execFile);

test('built extension executes in a separate Node process with private settings and progress', async () => {
  const root = await mkdtemp(join(tmpdir(), 'talos-js-'));
  try {
    await mkdir(join(root, 'src'));
    await writeFile(join(root, 'package.json'), JSON.stringify({ version: '1.0.0' }));
    await writeFile(
      join(root, 'src/index.mjs'),
      `
      import { defineExtension, settings } from '@thom1606/talos-sdk';
      import { writeFile } from 'node:fs/promises';
      export default defineExtension({ id: 'test.actions', name: 'Test', actions: [{
        id: 'write', title: { en: 'Write', nl: 'Schrijven' }, settings: [settings.password('password', 'Password')],
        async run(session) {
          if (session.settings.password !== 'test-only-secret') throw new Error('Settings did not arrive');
          await session.progress(0.5, 'Working');
          const output = session.files[0].path + '.result';
          await writeFile(output, 'original remains unchanged');
          await session.complete('Finished', [output]);
        }
      }] });`,
    );
    await execute(process.execPath, [resolve('sdk/build.mjs'), root]);
    const manifest = JSON.parse(await readFile(join(root, 'dist/module/config.json'), 'utf8'));
    const release = JSON.parse(await readFile(join(root, 'dist/release-config.json'), 'utf8'));
    assert.equal(release.release.asset, 'test.actions.talos');
    const archive = await readFile(join(root, 'dist/test.actions.talos'));
    assert.equal(archive.subarray(0, 2).toString(), 'PK');
    assert.equal(manifest.runtime, 'javascript');
    assert.equal(manifest.actions[0].settings[0].type, 'password');
    assert.equal(manifest.actions[0].translations.nl, 'Schrijven');
    const original = join(root, 'input.txt');
    await writeFile(original, 'original');
    const invocation = {
      protocolVersion: 1,
      taskID: randomUUID(),
      actionID: 'write',
      moduleID: 'test.actions',
      workspace: pathToFileURL(root).href,
      files: [{ url: pathToFileURL(original).href }],
    };
    const invocationPath = join(root, 'invocation.json');
    await writeFile(invocationPath, JSON.stringify(invocation));
    const child = spawn(process.execPath, [
      resolve('../../Talos/Resources/JavaScript/runner.mjs'),
      join(root, 'dist/module/extension.mjs'),
      invocationPath,
    ]);
    child.stdin.end(JSON.stringify({ password: 'test-only-secret' }));
    const status = await new Promise((accept, reject) => {
      child.once('error', reject);
      child.once('exit', accept);
    });
    assert.equal(status, 0);
    const events = (await readFile(join(root, 'events.jsonl'), 'utf8'))
      .trim()
      .split('\n')
      .map(JSON.parse);
    assert.deepEqual(
      events.map((event) => event.kind),
      ['progress', 'completed'],
    );
    assert.equal(await readFile(original, 'utf8'), 'original');
    assert.equal(await readFile(original + '.result', 'utf8'), 'original remains unchanged');
    assert.ok(!(await readFile(invocationPath, 'utf8')).includes('test-only-secret'));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('concurrent outputs never overwrite originals or each other', async () => {
  const root = await mkdtemp(join(tmpdir(), 'talos-output-'));
  try {
    const original = join(root, 'photo.png');
    await writeFile(original, 'original');
    const outputs = await Promise.all(
      ['first', 'second'].map((contents) =>
        outputFile(original, 'png', '', (path) => writeFile(path, contents)),
      ),
    );
    assert.equal(new Set(outputs).size, 2);
    assert.equal(await readFile(original, 'utf8'), 'original');
    assert.deepEqual(
      new Set(await Promise.all(outputs.map((path) => readFile(path, 'utf8')))),
      new Set(['first', 'second']),
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('translated action labels fall back to English and form descriptors stay serializable', () => {
  assert.equal(localize({ en: 'Upload', nl: 'Uploaden' }, 'nl-NL'), 'Uploaden');
  assert.equal(localize({ en: 'Upload' }, 'fr'), 'Upload');
  assert.equal(
    JSON.parse(JSON.stringify(settings.number('days', 'Days', { defaultValue: 7 }))).defaultValue,
    7,
  );
});
