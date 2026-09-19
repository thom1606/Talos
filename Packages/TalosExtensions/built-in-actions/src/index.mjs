import { defineExtension } from '@thom1606/talos-sdk';
import { convertAction } from './actions/convert.mjs';
import { archiveAction } from './actions/archive.mjs';
import { metadataAction } from './actions/metadata.mjs';
import { compressAction } from './actions/compress.mjs';
import { cropAction } from './actions/crop.mjs';

export default defineExtension({
  id: 'com.talos.actions',
  name: 'Talos Actions',
  description: 'Everyday file actions, included with Talos.',
  actions: [convertAction, archiveAction, metadataAction, compressAction, cropAction],
});
