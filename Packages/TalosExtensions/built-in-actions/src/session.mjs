import { basename } from 'node:path';

export const text = (en, nl, es, fr) => ({ en, nl, es, fr });
export const image = ['public.image'];
export const media = ['public.image', 'public.audio', 'public.movie'];
export const all = ['public.item', 'public.folder'];
export async function each(session, transform) {
  const outputs = [];
  for (const [index, file] of session.files.entries()) {
    await session.checkCancellation();
    await session.progress(index / session.files.length, basename(file.path));
    outputs.push(await transform(file));
  }
  await session.complete('Done', outputs);
}
