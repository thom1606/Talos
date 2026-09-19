import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readFile, mkdir, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
const execute = promisify(execFile);

await execute(process.execPath, [resolve('sdk/build.mjs'), 'built-in-actions']);
const extension = (
  await import(pathToFileURL(resolve('built-in-actions/dist/module/extension.mjs')))
).default;
function session(files) {
  return {
    files: files.map((path) => ({ path })),
    progress: async () => {},
    checkCancellation: async () => {},
    outputs: [],
    async complete(message, outputs) {
      this.outputs = outputs;
    },
  };
}

test('archive contains both same-named selections without modifying them', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'talos-zip-'));
  try {
    await mkdir(join(directory, 'one'));
    await mkdir(join(directory, 'two'));
    const first = join(directory, 'one/same.txt'),
      second = join(directory, 'two/same.txt');
    await writeFile(first, 'first');
    await writeFile(second, 'second');
    const context = session([first, second]);
    await extension.actions.find((action) => action.id === 'archive').run(context);
    assert.equal(context.outputs.length, 1);
    const unpacked = join(directory, 'unpacked');
    await execute('/usr/bin/ditto', ['-x', '-k', context.outputs[0], unpacked]);
    assert.equal(await readFile(join(unpacked, 'same.txt'), 'utf8'), 'first');
    assert.equal(await readFile(join(unpacked, '2-same.txt'), 'utf8'), 'second');
    assert.equal(await readFile(first, 'utf8'), 'first');
    assert.equal(await readFile(second, 'utf8'), 'second');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('native image conversion creates a real JPEG beside the untouched PNG', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'talos-image-'));
  try {
    const input = join(directory, 'image.png');
    const fixture = await readFile(resolve('../../Talos/TalosIcon.icon/Assets/1. base.png'));
    await writeFile(input, fixture);
    const context = session([input]);
    const action = extension.actions
      .find((action) => action.id === 'convert')
      .children.find((action) => action.id === 'convert.image.jpg');
    await action.run(context);
    const bytes = await readFile(context.outputs[0]);
    assert.equal(bytes[0], 0xff);
    assert.equal(bytes[1], 0xd8);
    assert.ok((await stat(context.outputs[0])).size > 0);
    assert.deepEqual(await readFile(input), fixture);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
