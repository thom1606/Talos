import { text, image } from '../session.mjs';

export const cropAction = {
  id: 'crop',
  title: text('Crop', 'Bijsnijden', 'Recortar', 'Recadrer'),
  symbol: 'crop',
  acceptedTypes: image,
  maximumFiles: 1,
  async run(session) {
    await session.crop(session.files[0].path);
  },
};
