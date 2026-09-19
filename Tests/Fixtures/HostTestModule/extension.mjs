import { stat, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
export default { actions: ['inspect', 'report'].map(id => ({ id, async run(session) {
  await session.progress(0.5, 'Inspecting');
  const report = await Promise.all(session.files.map(async file => ({ path: file.path, bytes: (await stat(file.path)).size })));
  const output = join(process.cwd(), 'report.json');
  await writeFile(output, JSON.stringify(report));
  await session.complete('Done', [output]);
} })) };
