import { talosWindow } from '@thom1606/talos-sdk/window';
import { previewSeconds, type AudioRange } from '../audio';

// Two short decoded buffers at most. FFmpeg supplies the same bleeped samples as export,
// so native browser codec support and timers cannot expose speech during the preview.
export class AudioPreview {
  private context: AudioContext | null = null;
  private generation = 0;
  private sources = new Map<AudioBufferSourceNode, () => void>();
  private clock: { media: number; audio: number } | null = null;

  get time() {
    return this.context && this.clock
      ? this.clock.media + Math.max(0, this.context.currentTime - this.clock.audio) : null;
  }

  stop() {
    this.generation++;
    this.clock = null;
    for (const [source, resolve] of this.sources) { source.onended = null; source.stop(); source.disconnect(); resolve(); }
    this.sources.clear();
    const context = this.context;
    this.context = null;
    if (context) void context.close().catch(() => {});
  }

  async play(index: number, start: number, duration: number, ranges: AudioRange[],
    onStart: () => void, onEnd: () => void, onError: (error: unknown) => void) {
    this.stop();
    const generation = this.generation;
    const context = new AudioContext();
    this.context = context;
    try {
      await context.resume();
      let position = start, nextAt = context.currentTime;
      let previous: Promise<void> | undefined;
      while (position < duration && generation === this.generation) {
        const base64 = await talosWindow.invoke<string>('audioPreview', {
          index, start: position, end: Math.min(duration, position + previewSeconds), ranges,
        });
        if (generation !== this.generation) return;
        const bytes = Uint8Array.from(atob(base64), character => character.charCodeAt(0));
        const buffer = await context.decodeAudioData(bytes.buffer);
        if (generation !== this.generation) return;
        if (!buffer.duration) throw new Error('Empty audio preview');
        const length = Math.min(buffer.duration, previewSeconds, duration - position);
        const at = Math.max(context.currentTime + 0.025, nextAt);
        // If decoding fell behind, keep the cursor aligned with what is actually audible.
        if (!this.clock || at > nextAt + 0.03) this.clock = { media: position, audio: at };
        const source = context.createBufferSource();
        source.buffer = buffer;
        source.connect(context.destination);
        const ended = new Promise<void>(resolve => {
          this.sources.set(source, resolve);
          source.onended = () => { source.disconnect(); this.sources.delete(source); resolve(); };
        });
        source.start(at, 0, length);
        if (position === start) onStart();
        nextAt = at + length;
        position += length;
        // Prefetch one buffer while its predecessor plays; never retain the whole recording.
        if (previous) await previous;
        previous = ended;
      }
      await previous;
      if (generation === this.generation) { this.stop(); onEnd(); }
    } catch (error) {
      if (generation === this.generation) { this.stop(); onError(error); }
    }
  }
}
