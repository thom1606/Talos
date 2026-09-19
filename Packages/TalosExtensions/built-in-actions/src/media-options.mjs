export const audioOptions = {
  mp3: ['-c:a', 'libmp3lame', '-q:a', '2'],
  wav: ['-c:a', 'pcm_s16le'],
  ogg: ['-c:a', 'libvorbis', '-q:a', '6'],
};
export const videoOptions = {
  mp4: ['-c:v', 'libx264', '-crf', '20', '-c:a', 'aac', '-movflags', '+faststart'],
  mov: ['-c:v', 'libx264', '-crf', '20', '-c:a', 'aac'],
  mkv: ['-c:v', 'libx264', '-crf', '20', '-c:a', 'aac'],
  avi: ['-c:v', 'mpeg4', '-q:v', '3', '-c:a', 'libmp3lame'],
  webm: ['-c:v', 'libvpx-vp9', '-crf', '30', '-b:v', '0', '-c:a', 'libopus'],
};
