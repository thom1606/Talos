import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdtemp, readdir, readFile, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { after, before, test } from 'node:test';
import { build } from '../node_modules/esbuild/lib/main.js';

const root = fileURLToPath(new URL('..', import.meta.url));
const codecs = join(root, 'vendor/bin', process.arch === 'arm64' ? 'arm64' : 'x86_64');
const ffmpeg = join(codecs, 'ffmpeg'), ffprobe = join(codecs, 'ffprobe');
const directory = await mkdtemp(join(tmpdir(), 'talos-audio-tests-'));
let operations;
const file = { name: 'stereo.wav', path: join(directory, 'stereo.wav'), contentType: 'public.wav' };
const context = { files: [file] };
const ranges = [{ start: 0.625, end: 1.375 }, { start: 2.2, end: 3 }, { start: 2.9, end: 3.4 }];
function encode(args) { execFileSync(ffmpeg, ['-nostdin', '-hide_banner', '-loglevel', 'error', '-n', ...args]); }
function samples(path) {
  const data = execFileSync(ffmpeg, ['-v', 'error', '-i', path, '-map', '0:a:0', '-f', 'f32le', '-c:a', 'pcm_f32le', '-'], { maxBuffer: 8 * 1024 * 1024 });
  return new Float32Array(data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength));
}
function metadata(path) { return JSON.parse(execFileSync(ffprobe, ['-v', 'error', '-show_streams', '-show_format', '-of', 'json', path])); }
function hash(bytes) { return createHash('sha256').update(bytes).digest('hex'); }

before(async () => {
  await build({ entryPoints: [join(root, 'src/operations/redact-audio.ts')], outfile: join(directory, 'operations.mjs'),
    bundle: true, platform: 'node', format: 'esm', target: 'node24', logLevel: 'silent' });
  await symlink(join(root, 'vendor'), join(directory, 'vendor'));
  operations = await import(pathToFileURL(join(directory, 'operations.mjs')).href);
  encode(['-f', 'lavfi', '-i', 'aevalsrc=0.2*sin(2*PI*440*t)|0.2*sin(2*PI*660*t):s=48000:d=4',
    '-c:a', 'pcm_s24le', '-metadata', 'title=Private source title', file.path]);
});
after(async () => { await rm(directory, { recursive: true, force: true }); });

test('export replaces samples on both channels, preserves other samples and never overwrites the source or an existing copy', async () => {
  const original = hash(await readFile(file.path));
  const result = await operations.redactAudio(context, { index: 0, ranges });
  assert.equal(result, join(directory, 'stereo-redacted.wav'));
  const source = samples(file.path), redacted = samples(result);
  assert.equal(source.length, redacted.length);
  for (let frame = 0; frame < source.length / 2; frame++) {
    const time = frame / 48000;
    const selected = ranges.some(range => time >= range.start && time < range.end);
    for (let channel = 0; channel < 2; channel++) {
      const expected = selected ? 0.18 * Math.sin(2 * Math.PI * 1000 * time) : source[frame * 2 + channel];
      assert.ok(Math.abs(redacted[frame * 2 + channel] - expected) < 2e-7, `Unexpected sample at ${time}s, channel ${channel}`);
    }
  }
  assert.equal(hash(await readFile(file.path)), original);
  const saved = hash(await readFile(result));
  const second = await operations.redactAudio(context, { index: 0, ranges });
  assert.equal(second, join(directory, 'stereo-redacted-2.wav'));
  assert.equal(hash(await readFile(result)), saved);
  const info = metadata(result);
  assert.equal(info.streams.length, 1);
  assert.equal(info.streams[0].channels, 2);
  assert.equal(info.format.tags?.title, undefined);
});

test('waveform summaries are bounded, include a requested zoom region and preserve phase-inverted stereo', async () => {
  const wave = await operations.audioWaveform(context, { index: 0 });
  assert.equal(wave.duration, 4);
  assert.ok(wave.peaks.length > 900 && wave.peaks.length <= 1024);
  assert.ok(wave.peaks.every(value => Number.isFinite(value) && value > 0.1 && value <= 1));
  const zoom = await operations.audioWaveform(context, { index: 0, start: 1, end: 1.5 });
  assert.equal(zoom.start, 1); assert.equal(zoom.end, 1.5);
  const inverted = { name: 'inverted.wav', path: join(directory, 'inverted.wav') };
  encode(['-f', 'lavfi', '-i', 'aevalsrc=0.2*sin(2*PI*440*t)|-0.2*sin(2*PI*440*t):s=48000:d=1', '-c:a', 'pcm_s24le', inverted.path]);
  const phase = await operations.audioWaveform({ files: [inverted] }, { index: 0 });
  assert.ok(phase.peaks.every(value => value > 0.1));
});

test('bounded preview applies the same tone at an absolute seek position, then removes its temporary file', async () => {
  const before = (await readdir(tmpdir())).filter(name => name.startsWith('talos-audio-preview-'));
  const encoded = await operations.audioPreview(context, { index: 0, start: 0.8, end: 1.2, ranges });
  const bytes = Buffer.from(encoded, 'base64');
  assert.ok(Buffer.byteLength(JSON.stringify(encoded)) > 32768, 'Uncompressed preview exceeds the former response cap');
  const path = join(directory, 'preview.wav');
  await writeFile(path, bytes);
  const decoded = samples(path);
  const rate = Number(metadata(path).streams[0].sample_rate);
  assert.equal(metadata(path).streams[0].codec_name, 'pcm_s16le');
  // Independently check the tone and absence of source audio after an absolute seek.
  function magnitude(frequency) {
    let real = 0, imaginary = 0, count = 0;
    for (let frame = Math.floor(rate * 0.08); frame < Math.floor(rate * 0.32); frame++) {
      real += decoded[frame * 2] * Math.cos(2 * Math.PI * frequency * frame / rate);
      imaginary += decoded[frame * 2] * Math.sin(2 * Math.PI * frequency * frame / rate);
      count++;
    }
    return Math.hypot(real, imaginary) * 2 / count;
  }
  assert.ok(magnitude(1000) > 0.14);
  assert.ok(magnitude(440) < 0.003);
  assert.ok(magnitude(660) < 0.003);
  await rm(path);
  const full = await operations.audioPreview(context, { index: 0, start: 0, end: 2, ranges });
  assert.ok(Buffer.byteLength(JSON.stringify(full)) > 32768);
  assert.deepEqual((await readdir(tmpdir())).filter(name => name.startsWith('talos-audio-preview-')), before);
});

test('AAC and FLAC inputs preview and export; extra unredacted tracks are excluded', async () => {
  for (const [extension, codec] of [['m4a', 'aac'], ['flac', 'flac']]) {
    const audio = { name: `encoded.${extension}`, path: join(directory, `encoded.${extension}`) };
    encode(['-i', file.path, '-c:a', codec, ...(extension === 'm4a' ? ['-b:a', '192k'] : []), audio.path]);
    const ctx = { files: [audio] };
    const wave = await operations.audioWaveform(ctx, { index: 0 });
    assert.ok(wave.duration >= 4 && wave.duration < 4.1);
    await operations.audioPreview(ctx, { index: 0, start: 1, end: 2, ranges: [{ start: 1, end: 2 }] });
    const saved = await operations.redactAudio(ctx, { index: 0, ranges: [{ start: 1, end: 2 }] });
    assert.equal(metadata(saved).streams[0].codec_name, 'pcm_s24le');
  }
  const multi = { name: 'tracks.m4a', path: join(directory, 'tracks.m4a') };
  encode(['-i', file.path, '-map', '0:a:0', '-map', '0:a:0', '-c:a', 'aac', multi.path]);
  assert.equal(metadata(multi.path).streams.length, 2);
  const saved = await operations.redactAudio({ files: [multi] }, { index: 0, ranges: [{ start: 0, end: 4 }] });
  assert.equal(metadata(saved).streams.length, 1);
});

test('invalid intervals, unsupported files and cancelled work cannot publish an output', async () => {
  const before = (await readdir(directory)).sort();
  for (const invalid of [[], [{ start: -1, end: 1 }], [{ start: 2, end: 1 }], [{ start: 0, end: Infinity }],
    [{ start: NaN, end: 1 }], [{ start: 0, end: 5 }], [{ start: '0', end: 1 }], Array(129).fill({ start: 0, end: 1 })]) {
    await assert.rejects(operations.redactAudio(context, { index: 0, ranges: invalid }));
  }
  await assert.rejects(operations.redactAudio(context, { index: -1, ranges }));
  await assert.rejects(operations.redactAudio({ files: [{ ...file, name: 'not-audio.png' }] }, { index: 0, ranges }));
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(operations.redactAudio(context, { index: 0, ranges }, controller.signal));
  assert.deepEqual((await readdir(directory)).sort(), before);
});
