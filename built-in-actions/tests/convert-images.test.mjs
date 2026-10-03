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
const directory = await mkdtemp(join(tmpdir(), 'talos-convert-images-'));
const file = { name: 'photo "één".png', path: join(directory, 'photo "één".png') };
const width = 64, height = 48, rgba = Buffer.alloc(width * height * 4);
let convert;
function hash(bytes) { return createHash('sha256').update(bytes).digest('hex'); }
function sips(input, output, format, args = []) {
  execFileSync('/usr/bin/sips', [...args, '-s', 'format', format, input, '--out', output], { stdio: 'pipe' });
}
function pixel(image, x, y) { return [...image.pixels.subarray((y * image.width + x) * 4, (y * image.width + x) * 4 + 4)]; }
function closeColor(actual, expected, tolerance = 8) {
  for (let channel = 0; channel < 3; channel++) assert.ok(Math.abs(actual[channel] - expected[channel]) <= tolerance, `${actual} != ${expected}`);
}

before(async () => {
  for (const operation of ['convert', 'png']) {
    await build({ entryPoints: [join(root, `src/operations/${operation}.ts`)], outfile: join(directory, `${operation}.mjs`),
      bundle: true, platform: 'node', format: 'esm', target: 'node24', logLevel: 'silent' });
  }
  await symlink(join(root, 'vendor'), join(directory, 'vendor'));
  ({ convert } = await import(pathToFileURL(join(directory, 'convert.mjs')).href));
  const { encodePNG } = await import(pathToFileURL(join(directory, 'png.mjs')).href);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const offset = (y * width + x) * 4;
      rgba.set(x < width / 2 ? [220, 45, 35] : [35, 110, 180], offset);
      rgba[offset + 3] = x >= width * 3 / 4 ? 0 : x >= width / 2 ? 128 : y >= height * 3 / 4 ? 51 : 255;
    }
  }
  await writeFile(file.path, await encodePNG(width, height, rgba));
});
after(async () => { await rm(directory, { recursive: true, force: true }); });

test('real WebP export preserves every alpha value, dimensions, originals and existing copies', async () => {
  const original = hash(await readFile(file.path));
  const [result] = await convert({ files: [file] }, 'webp');
  assert.equal(result, join(directory, 'photo "één"-converted.webp'));
  const bytes = await readFile(result);
  assert.equal(bytes.toString('ascii', 0, 4), 'RIFF'); assert.equal(bytes.toString('ascii', 8, 12), 'WEBP');
  const image = decodeImage(ffmpeg, result);
  assert.equal(image.width, width); assert.equal(image.height, height);
  for (let offset = 3; offset < rgba.length; offset += 4) assert.equal(image.pixels[offset], rgba[offset], `Alpha at pixel ${(offset - 3) / 4}`);
  closeColor(pixel(image, 10, 10), [220, 45, 35]);
  closeColor(pixel(image, 40, 10), [35, 110, 180]);
  const [second] = await convert({ files: [file] }, 'webp');
  assert.equal(second, join(directory, 'photo "één"-converted-2.webp'));
  assert.equal(hash(await readFile(result)), hash(bytes)); assert.equal(hash(await readFile(file.path)), original);
  assert.ok(!(await readdir(directory)).some(name => name.startsWith('.talos-output-')));
});

test('JPEG, TIFF, BMP, GIF, HEIC and WebP inputs convert with one output per image', async () => {
  const files = [];
  for (const [extension, format] of [['jpg', 'jpeg'], ['tiff', 'tiff'], ['bmp', 'bmp'], ['gif', 'gif'], ['heic', 'heic']]) {
    const input = { name: `input.${extension}`, path: join(directory, `input.${extension}`) };
    sips(file.path, input.path, format); files.push(input);
  }
  const outputs = await convert({ files }, 'webp');
  assert.equal(outputs.length, files.length); assert.equal(new Set(outputs).size, files.length);
  for (const path of outputs) {
    const image = decodeImage(ffmpeg, path);
    assert.equal(image.width, width); assert.equal(image.height, height);
  }
  const webp = { name: 'input-converted.webp', path: outputs[0] };
  const [roundtrip] = await convert({ files: [webp] }, 'webp');
  assert.equal(decodeImage(ffmpeg, roundtrip).width, width);
  // The existing reverse WebP-to-PNG route must remain available.
  const [png] = await convert({ files: [webp] }, 'png');
  assert.equal(decodeImage(ffmpeg, png).height, height);
});

test('EXIF rotation is baked into pixels and wide-gamut input is converted to sRGB', async () => {
  const rotated = { name: 'rotated.jpg', path: join(directory, 'rotated.jpg') };
  const jpeg = join(directory, 'plain.jpg');
  sips(file.path, jpeg, 'jpeg');
  const bytes = await readFile(jpeg);
  // A standard EXIF/TIFF Orientation=6 record, independent of ImageIO's writer.
  const exif = Buffer.from('45786966000049492a0008000000010012010300010000000600000000000000', 'hex');
  const marker = Buffer.alloc(4); marker.writeUInt16BE(0xffe1); marker.writeUInt16BE(exif.length + 2, 2);
  await writeFile(rotated.path, Buffer.concat([bytes.subarray(0, 2), marker, exif, bytes.subarray(2)]));
  const source = decodeImage(ffmpeg, jpeg);
  const [path] = await convert({ files: [rotated] }, 'webp');
  const result = decodeImage(ffmpeg, path);
  assert.equal(result.width, height); assert.equal(result.height, width);
  closeColor(pixel(result, height - 1 - 10, 10), pixel(source, 10, 10));
  closeColor(pixel(result, height - 1 - 10, 40), pixel(source, 40, 10), 12);
  const p3 = { name: 'p3.png', path: join(directory, 'p3.png') };
  const expected = join(directory, 'sRGB.png');
  sips(file.path, p3.path, 'png', ['-e', '/System/Library/ColorSync/Profiles/Display P3.icc']);
  sips(p3.path, expected, 'png', ['-m', '/System/Library/ColorSync/Profiles/sRGB Profile.icc']);
  const [output] = await convert({ files: [p3] }, 'webp');
  closeColor(pixel(decodeImage(ffmpeg, output), 10, 10), pixel(decodeImage(ffmpeg, expected), 10, 10));
});

test('invalid and cancelled conversion publishes nothing; WebP is exposed only for supported images', async () => {
  const corrupt = { name: 'bad.png', path: join(directory, 'bad.png') };
  await writeFile(corrupt.path, 'Not an image');
  const before = (await readdir(directory)).sort();
  await assert.rejects(convert({ files: [corrupt] }, 'webp'));
  await assert.rejects(convert({ files: [{ ...file, name: 'audio.wav' }] }, 'webp'));
  const controller = new AbortController();
  const pending = convert({ files: [file] }, 'webp', controller.signal);
  setTimeout(() => controller.abort(), 5);
  await assert.rejects(pending);
  assert.deepEqual((await readdir(directory)).sort(), before);
  const manifest = JSON.parse(await readFile(join(root, 'package.json'), 'utf8'));
  const action = manifest.commands.find(command => command.name === 'convert-webp');
  assert.ok(manifest.commands.find(command => command.name === 'convert').subcommands.includes(action.name));
  assert.ok(action.supportedFileTypes.includes('public.heic'));
  assert.ok(!action.supportedFileTypes.includes('public.audio') && !action.supportedFileTypes.includes('com.adobe.pdf'));
  for (const path of Object.values(manifest.talos.locales)) {
    assert.equal(JSON.parse(await readFile(join(root, path), 'utf8')).commands['convert-webp'].displayName, 'WebP');
  }
});
