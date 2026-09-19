import { outputFile } from '../files.mjs';
import { each, text, image } from '../session.mjs';

export const metadataAction = {
  id: 'metadata',
  title: text(
    'Remove metadata',
    'Metadata wissen',
    'Quitar metadatos',
    'Supprimer les métadonnées',
  ),
  symbol: 'tag.slash',
  acceptedTypes: image,
  async run(session) {
    await each(session, (file) =>
      outputFile(file.path, 'png', '-clean', (output) =>
        session.image({ input: file.path, output, stripMetadata: true }),
      ),
    );
  },
};
