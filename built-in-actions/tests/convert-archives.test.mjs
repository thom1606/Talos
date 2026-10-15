import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { copyFile, mkdtemp, readdir, readFile, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { after, before, test } from 'node:test';
import { build } from '../node_modules/esbuild/lib/main.js';

const root = fileURLToPath(new URL('..', import.meta.url));
const directory = await mkdtemp(join(tmpdir(), 'talos-convert-archives-'));
const input = { name: 'files "één".zip', path: join(directory, 'files "één".zip') };
let convert, expected;
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
// Independent writers/readers check actual archives without extracting their paths.
const python = String.raw`
import base64, io, json, stat, sys, tarfile, zipfile
operation, path = sys.argv[1:]
if operation == 'fixture':
    with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        entries = [('nested/file "één"\n.txt', b'Hello archives\x00\xff', stat.S_IFREG | 0o644),
                   ('.hidden', b'hidden', stat.S_IFREG | 0o600),
                   ('__MACOSX/._file.txt', b'AppleDouble entry', stat.S_IFREG | 0o644),
                   ('decomposed-e\u0301.txt', b'Unicode path', stat.S_IFREG | 0o644),
                   ('empty.txt', b'', stat.S_IFREG | 0o644),
                   ('empty/', b'', stat.S_IFDIR | 0o755),
                   ('executable', b'#!/bin/sh\nexit 0\n', stat.S_IFREG | 0o755),
                   ('relative-link', b'nested/file "\xc3\xa9\xc3\xa9n"\n.txt', stat.S_IFLNK | 0o777),
                   ('outside-link', b'../sentinel.txt', stat.S_IFLNK | 0o777)]
        for name, data, mode in entries:
            info = zipfile.ZipInfo(name)
            info.create_system = 3
            info.external_attr = mode << 16 | (0x10 if stat.S_ISDIR(mode) else 0)
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data)
elif operation == 'hardlinks':
    with tarfile.open(path, 'w') as archive:
        regular = tarfile.TarInfo('file.txt')
        regular.size = 6
        archive.addfile(regular, io.BytesIO(b'sample'))
        link = tarfile.TarInfo('copy.txt')
        link.type, link.linkname = tarfile.LNKTYPE, 'file.txt'
        archive.addfile(link)
elif operation == 'large':
    with zipfile.ZipFile(path, 'w') as archive:
        archive.writestr('large.bin', bytes(128 * 1024 * 1024))
elif operation == 'empty':
    with zipfile.ZipFile(path, 'w'): pass
elif operation == 'read':
    result = []
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            for entry in archive.infolist():
                mode = entry.external_attr >> 16
                kind = 'directory' if entry.is_dir() else 'symlink' if stat.S_ISLNK(mode) else 'file'
                data = archive.read(entry)
                result.append(dict(name=entry.filename.rstrip('/'), kind=kind, mode=mode & 0o777,
                                   data=base64.b64encode(data).decode()))
    else:
        with tarfile.open(path, 'r:*') as archive:
            for entry in archive.getmembers():
                kind = 'directory' if entry.isdir() else 'symlink' if entry.issym() else 'hardlink' if entry.islnk() else 'file'
                data = entry.linkname.encode() if kind in ('symlink', 'hardlink') else archive.extractfile(entry).read() if entry.isfile() else b''
                result.append(dict(name=entry.name.rstrip('/'), kind=kind, mode=entry.mode & 0o777,
                                   data=base64.b64encode(data).decode()))
    print(json.dumps(sorted(result, key=lambda entry: entry['name'])))
`;
function archive(operation, path) {
  const result = execFileSync('python3', ['-c', python, operation, path], { encoding: 'utf8' });
  return operation === 'read' ? JSON.parse(result) : undefined;
}
function file(path) { return { path, name: path.slice(path.lastIndexOf('/') + 1) }; }
async function assertNoStaging() {
  assert.ok(!(await readdir(directory)).some(name => name.startsWith('.talos-output-')));
}
before(async () => {
  await build({ entryPoints: [join(root, 'src/operations/convert.ts')], outfile: join(directory, 'convert.mjs'),
    bundle: true, platform: 'node', format: 'esm', target: 'node24', logLevel: 'silent' });
  await symlink(join(root, 'vendor'), join(directory, 'vendor'));
  ({ convert } = await import(pathToFileURL(join(directory, 'convert.mjs')).href));
  archive('fixture', input.path);
  expected = archive('read', input.path).map(entry => ({ ...entry, name: entry.name.normalize('NFC') }));
  await writeFile(join(directory, 'sentinel.txt'), 'Never read or replace this link target');
});
after(async () => { await rm(directory, { recursive: true, force: true }); });

test('ZIP, TAR and GZIP round trips preserve bytes, paths, directories, permissions and links', async () => {
  const original = hash(await readFile(input.path));
  const sentinel = await readFile(join(directory, 'sentinel.txt'));
  for (const format of ['zip', 'tar', 'gzip']) {
    const [output] = await convert({ files: [input] }, format);
    assert.equal(output, join(directory, `files "één"-converted.${format === 'gzip' ? 'tgz' : format}`));
    assert.deepEqual(archive('read', output), expected);
    for (const target of ['zip', 'tar', 'gzip']) {
      const [roundtrip] = await convert({ files: [file(output)] }, target);
      assert.deepEqual(archive('read', roundtrip), expected, `${format} -> ${target}`);
    }
  }
  assert.equal(hash(await readFile(input.path)), original);
  assert.deepEqual(await readFile(join(directory, 'sentinel.txt')), sentinel);
  assert.ok(!(await readdir(directory)).includes('nested'), 'Entries must never be extracted');
  await assertNoStaging();
});

test('compound suffixes and batches create collision-safe copies alongside each original', async () => {
  const source = join(directory, 'files "één"-converted.tgz');
  const files = [];
  for (const suffix of ['.tar.gz', '.tar.gzip', '.TGZ']) {
    const path = join(directory, `batch${suffix}`);
    await copyFile(source, path); files.push(file(path));
  }
  const outputs = await convert({ files }, 'zip');
  assert.deepEqual(outputs.map(path => file(path).name), ['batch-converted.zip', 'batch-converted-2.zip', 'batch-converted-3.zip']);
  for (const output of outputs) assert.deepEqual(archive('read', output), expected);
  const bytes = await readFile(outputs[0]);
  const [next] = await convert({ files: [files[0]] }, 'zip');
  assert.equal(file(next).name, 'batch-converted-4.zip');
  assert.deepEqual(await readFile(outputs[0]), bytes);
  await assertNoStaging();
});

test('empty archives stay valid; TAR and GZIP preserve hardlinks', async () => {
  const empty = join(directory, 'empty.zip'); archive('empty', empty);
  for (const format of ['zip', 'tar', 'gzip']) {
    const [output] = await convert({ files: [file(empty)] }, format);
    assert.deepEqual(archive('read', output), []);
  }
  const linked = join(directory, 'hardlinks.tar'); archive('hardlinks', linked);
  for (const format of ['tar', 'gzip']) {
    const [output] = await convert({ files: [file(linked)] }, format);
    assert.deepEqual(archive('read', output), archive('read', linked));
  }
});

test('corrupt, encrypted and partially representable archives never publish an incomplete copy', async () => {
  const bad = join(directory, 'corrupt.zip'); await writeFile(bad, 'Not an archive');
  const crc = join(directory, 'bad-crc.zip');
  execFileSync('python3', ['-c', 'import sys,zipfile; z=zipfile.ZipFile(sys.argv[1],"w"); z.writestr("file.txt",b"unique-content"); z.close()', crc]);
  const damaged = await readFile(crc); damaged[damaged.indexOf('unique-content')] ^= 0xff; await writeFile(crc, damaged);
  const encrypted = join(directory, 'encrypted.zip');
  execFileSync('/usr/bin/zip', ['-j', '-P', 'test-only', encrypted, join(directory, 'sentinel.txt')], { stdio: 'pipe' });
  const before = (await readdir(directory)).sort();
  for (const path of [bad, crc, encrypted, join(directory, 'hardlinks.tar')]) {
    // libarchive warns that ZIP cannot represent this hardlink; silently continuing loses an entry.
    const signal = AbortSignal.timeout(5_000);
    await assert.rejects(convert({ files: [file(path)] }, 'zip', signal));
    assert.ok(!signal.aborted, 'Invalid input must fail immediately without prompting for a password');
  }
  assert.deepEqual((await readdir(directory)).sort(), before);
  await assertNoStaging();
});

test('cancellation cleans up a running conversion and exposes only supported archive commands', async () => {
  const large = join(directory, 'large.zip'); archive('large', large);
  const before = (await readdir(directory)).sort();
  const controller = new AbortController();
  const pending = convert({ files: [file(large)] }, 'gzip', controller.signal);
  setTimeout(() => controller.abort(), 20);
  await assert.rejects(pending);
  await assert.rejects(convert({ files: [input] }, 'rar'));
  await assert.rejects(convert({ files: [file(join(directory, 'plain.gz'))] }, 'zip'));
  await assert.rejects(convert({ files: [input, file(join(directory, 'image.png'))] }, 'zip'));
  assert.deepEqual((await readdir(directory)).sort(), before);
  await assertNoStaging();
  const manifest = JSON.parse(await readFile(join(root, 'package.json'), 'utf8'));
  const parent = manifest.commands.find(command => command.name === 'convert');
  for (const format of ['zip', 'tar', 'gzip']) {
    const action = manifest.commands.find(command => command.name === `convert-${format}`);
    assert.ok(parent.subcommands.includes(action.name));
    assert.ok(action.supportedFileTypes.includes('public.zip-archive'));
    assert.ok(action.supportedFileTypes.includes('.tar.gz'));
    assert.ok(!action.supportedFileTypes.includes('public.audio'));
    for (const path of Object.values(manifest.talos.locales)) {
      assert.equal(JSON.parse(await readFile(join(root, path), 'utf8')).commands[action.name].displayName, format.toUpperCase());
    }
  }
  assert.ok(!manifest.commands.some(command => command.name === 'convert-rar'));
});
