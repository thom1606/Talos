// Media policy belongs to this extension, never to Talos or its SDK.
export type MediaKind = 'image' | 'video' | 'audio';
export function mediaKind(name: string): MediaKind | undefined {
  if (/\.(png|jpe?g|heic|heif|tiff?|webp|gif|bmp)$/i.test(name)) return 'image';
  if (/\.(mp4|mov|m4v|mkv|webm|avi|mpeg|mpg)$/i.test(name)) return 'video';
  if (/\.(wav|aiff?|flac|alac|m4a|aac|mp3|ogg|opus)$/i.test(name)) return 'audio';
}
export const formats = { image: ['png', 'jpg', 'tiff', 'bmp'], video: ['mp4', 'mov'], audio: ['m4a', 'wav', 'flac'] } as const;
