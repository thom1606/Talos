import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdtemp, readdir, readFile, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { after, before, test } from 'node:test';
import { build } from '../node_modules/esbuild/lib/main.js';
import { decodeImage } from './image-pixels.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));
const ffmpeg = join(root, 'vendor/bin', process.arch === 'arm64' ? 'arm64' : 'x86_64', 'ffmpeg');
const directory = await mkdtemp(join(tmpdir(), 'talos-convert-audio-'));
const file = { name: 'levels.wav', path: join(directory, 'levels.wav'), contentType: 'public.wav' };
let convert, optimizePNG;
function encode(args) { execFileSync(ffmpeg, ['-nostdin', '-hide_banner', '-loglevel', 'error', '-n', ...args]); }
function pixels(path) { return decodeImage(ffmpeg, path).pixels; }
function hash(bytes) { return createHash('sha256').update(bytes).digest('hex'); }

before(async () => {
  for (const operation of ['convert', 'png']) {
    await build({ entryPoints: [join(root, `src/operations/${operation}.ts`)], outfile: join(directory, `${operation}.mjs`),
      bundle: true, platform: 'node', format: 'esm', target: 'node24', logLevel: 'silent' });
  }
  await symlink(join(root, 'vendor'), join(directory, 'vendor'));
  ({ convert } = await import(pathToFileURL(join(directory, 'convert.mjs')).href));
  ({ optimizePNG } = await import(pathToFileURL(join(directory, 'png.mjs')).href));
  // Distinct silence/quiet/loud regions make lost amplitude or timing visible in actual output pixels.
  encode(['-f', 'lavfi', '-i', "aevalsrc='if(lt(t,1),0,if(lt(t,2),0.1,0.81))*sin(2*PI*440*t)':s=48000:d=3",
    '-c:a', 'pcm_s24le', '-metadata', 'title=Private recording', file.path]);
});
after(async () => { await rm(directory, { recursive: true, force: true }); });

test('audio converts to a transparent branded PNG and scalable SVG with the real amplitude envelope', async () => {
  const original = hash(await readFile(file.path));
  const [png] = await convert({ files: [file] }, 'png');
  const [svg] = await convert({ files: [file] }, 'svg');
  assert.equal(png, join(directory, 'levels-converted.png'));
  assert.equal(svg, join(directory, 'levels-converted.svg'));
  const bytes = await readFile(png), source = await readFile(svg, 'utf8');
  assert.equal(bytes.readUInt32BE(16), 1600); assert.equal(bytes.readUInt32BE(20), 400);
  assert.equal(bytes[25], 6, 'PNG keeps its alpha channel');
  assert.match(source, /viewBox="0 0 1600 400"/);
  const accent = (await readFile(join(root, '../Talos/Core/Appearance/TalosAppearance.swift'), 'utf8')).match(/accentHex = "(#[A-Fa-f0-9]{6})"/)[1];
  assert.ok(source.includes(`fill="${accent}"`));
  assert.ok(!source.includes('Private recording') && !source.includes(file.name));
  const bars = [...source.matchAll(/<rect x="([^"]+)" y="([^"]+)" width="([^"]+)" height="([^"]+)" rx="([^"]+)"\/>/g)]
    .map(match => match.slice(1).map(Number));
  assert.equal(bars.length, 512);
  assert.equal(bars[85][3], 2);
  assert.ok(bars[256][3] > 110 && bars[256][3] < 120);
  assert.ok(bars[426][3] > 330 && bars[426][3] < 333);
  const rgba = pixels(png), rgb = Buffer.from(accent.slice(1), 'hex');
  assert.equal(rgba.length, 1600 * 400 * 4);
  let transparent = 0, painted = 0, antialiased = 0;
  for (let offset = 0; offset < rgba.length; offset += 4) {
    if (!rgba[offset + 3]) { transparent++; continue; }
    assert.deepEqual(rgba.subarray(offset, offset + 3), rgb);
    painted++;
    if (rgba[offset + 3] < 255) antialiased++;
  }
  assert.ok(transparent > 300_000 && painted > 30_000 && antialiased > 0);
  for (const index of [85, 256, 426]) {
    const [x, , width, height] = bars[index];
    const column = Math.floor(x + width / 2);
    const rows = Array.from({ length: 400 }, (_, y) => rgba[(y * 1600 + column) * 4 + 3]);
    assert.ok(Math.abs(rows.filter(alpha => alpha > 0).length - height) < 2);
    assert.equal(rows[0], 0); assert.equal(rows.at(-1), 0);
  }
  assert.equal(hash(await readFile(file.path)), original);
  const pngHash = hash(bytes), svgHash = hash(source);
  assert.deepEqual(await convert({ files: [file] }, 'png'), [join(directory, 'levels-converted-2.png')]);
  assert.deepEqual(await convert({ files: [file] }, 'svg'), [join(directory, 'levels-converted-2.svg')]);
  assert.equal(hash(await readFile(png)), pngHash); assert.equal(hash(await readFile(svg)), svgHash);
  const optimized = join(directory, 'optimized.png');
  await writeFile(optimized, await optimizePNG(png));
  assert.deepEqual(pixels(optimized), rgba, 'Shared PNG chunk handling also preserves existing optimization');
});

test('compressed and phase-inverted audio produces waveforms, including one output per selected file', async () => {
  const files = [];
  for (const [extension, codec] of [['m4a', 'aac'], ['flac', 'flac']]) {
    const audio = { name: `encoded.${extension}`, path: join(directory, `encoded.${extension}`) };
    encode(['-i', file.path, '-c:a', codec, audio.path]); files.push(audio);
  }
  const outputs = await convert({ files }, 'svg');
  assert.equal(outputs.length, 2);
  assert.notEqual(outputs[0], outputs[1], 'Repeated basenames receive collision-safe output names');
  for (const path of outputs) {
    const svg = await readFile(path, 'utf8');
    assert.ok([...svg.matchAll(/height="([\d.]+)" rx=/g)].some(match => Number(match[1]) > 300));
  }
  const inverted = { name: 'inverted.wav', path: join(directory, 'inverted.wav') };
  encode(['-f', 'lavfi', '-i', 'aevalsrc=0.2*sin(2*PI*440*t)|-0.2*sin(2*PI*440*t):s=48000:d=0.1', '-c:a', 'pcm_s24le', inverted.path]);
  const [png] = await convert({ files: [inverted] }, 'png');
  const rgba = pixels(png);
  const visible = Array.from({ length: 1600 }, (_, x) => rgba[(130 * 1600 + x) * 4 + 3]).filter(alpha => alpha > 0);
  assert.ok(visible.length > 128, 'Inverted stereo retains its full waveform even on a short clip');
  const silent = { name: 'silence.wav', path: join(directory, 'silence.wav') };
  encode(['-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=mono', '-t', '0.05', silent.path]);
  const [svg] = await convert({ files: [silent] }, 'svg');
  const heights = [...(await readFile(svg, 'utf8')).matchAll(/height="([\d.]+)" rx=/g)].map(match => Number(match[1]));
  assert.equal(heights.length, 512); assert.ok(heights.every(height => height === 2));
});

test('invalid or cancelled conversion leaves no output or staging directory', async () => {
  const corrupt = { name: 'corrupt.wav', path: join(directory, 'corrupt.wav') };
  await writeFile(corrupt.path, 'Not audio');
  const before = (await readdir(directory)).sort();
  await assert.rejects(convert({ files: [file] }, 'jpg'));
  await assert.rejects(convert({ files: [{ ...file, name: 'image.png' }] }, 'svg'));
  await assert.rejects(convert({ files: [corrupt] }, 'png'));
  const controller = new AbortController();
  const converting = convert({ files: [file] }, 'svg', controller.signal);
  setTimeout(() => controller.abort(), 5);
  await assert.rejects(converting);
  assert.deepEqual((await readdir(directory)).sort(), before);
});

test('the audio submenu exposes SVG/PNG and every locale has the SVG action', async () => {
  const manifest = JSON.parse(await readFile(join(root, 'package.json'), 'utf8'));
  assert.ok(manifest.commands.find(command => command.name === 'convert').subcommands.includes('convert-svg'));
  assert.deepEqual(manifest.commands.find(command => command.name === 'convert-svg').supportedFileTypes, ['public.audio']);
  assert.ok(manifest.commands.find(command => command.name === 'convert-png').supportedFileTypes.includes('public.audio'));
  for (const path of Object.values(manifest.talos.locales)) {
    const locale = JSON.parse(await readFile(join(root, path), 'utf8'));
    assert.equal(locale.commands['convert-svg'].displayName, 'SVG');
  }
});
