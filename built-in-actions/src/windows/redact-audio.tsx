import { useEffect, useState } from 'react';
import { Button, Text, t } from '@thom1606/talos-sdk/react';
import { talosWindow } from '@thom1606/talos-sdk/window';
import { PauseIcon, PlayIcon } from '@radix-ui/react-icons';
import { audioTime, type AudioRange, type AudioWaveform } from '../audio';
import { AudioPreview } from './audio-preview';
import { AudioWaveformView, type AudioSelection } from './audio-waveform';
import './redact-audio.css';

export default function AudioRedactWindow({ index, onBusyChange }: {
  index: number; onBusyChange(busy: boolean): void;
}) {
  const [waveform, setWaveform] = useState<AudioWaveform | null>(null);
  const [view, setView] = useState<AudioRange | undefined>();
  const [selections, setSelections] = useState<AudioSelection[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [starting, setStarting] = useState(false);
  const [playing, setPlaying] = useState(false);
  const [time, setTime] = useState(0);
  const [error, setError] = useState('');
  const [preview] = useState(() => new AudioPreview());
  const busy = loading || saving;

  useEffect(() => { onBusyChange(busy); }, [busy, onBusyChange]);
  useEffect(() => () => preview.stop(), [preview]);
  useEffect(() => {
    let cancelled = false;
    setLoading(true); setError('');
    talosWindow.invoke<AudioWaveform>('audioWaveform', { index, ...view }).then(data => {
      if (!cancelled) setWaveform(data);
    }).catch(error => { if (!cancelled) setError(message(error)); }).finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [index, view]);
  useEffect(() => {
    if (!playing) return;
    let frame = 0;
    function update() { const next = preview.time; if (next !== null) setTime(Math.min(next, waveform?.duration ?? next)); frame = requestAnimationFrame(update); }
    frame = requestAnimationFrame(update);
    return () => cancelAnimationFrame(frame);
  }, [playing, waveform?.duration, preview]);

  function pause() {
    const next = preview.time;
    if (next !== null) setTime(Math.min(next, waveform?.duration ?? next));
    preview.stop(); setPlaying(false); setStarting(false);
  }
  function seek(next: number) { pause(); setTime(next); }
  function play() {
    if (!waveform) return;
    if (playing || starting) { pause(); return; }
    setError(''); setStarting(true);
    const start = time >= waveform.duration - 0.001 ? 0 : time;
    setTime(start);
    void preview.play(index, start, waveform.duration, selections,
      () => { setStarting(false); setPlaying(true); },
      () => { setPlaying(false); setTime(waveform.duration); },
      error => { setStarting(false); setPlaying(false); setError(message(error)); });
  }
  function zoom(factor: number, center: number) {
    if (!waveform || busy) return;
    pause();
    const span = Math.min(waveform.duration, Math.max(0.25, (waveform.end - waveform.start) * factor));
    const start = Math.max(0, Math.min(waveform.duration - span, center - span / 2));
    setView({ start, end: Math.min(waveform.duration, start + span) });
  }
  async function save() {
    pause(); setSaving(true); setError('');
    try {
      await talosWindow.invoke('redactAudio', { index, ranges: selections.map(({ start, end }) => ({ start, end })) });
      await talosWindow.close();
    } catch (error) { setError(message(error)); }
    finally { setSaving(false); }
  }
  return <main className="audio-redact" aria-busy={busy}>
    <div className="audio-stage">
      {waveform ?
        <AudioWaveformView waveform={waveform} selections={selections} selected={selected} time={time} disabled={busy}
          onSelect={setSelected} onChange={setSelections} onSeek={seek} onEdit={pause} onZoom={zoom} />
        : <Text tone="secondary" role="status">{loading ? t('redact.audioOpening') : t('redact.audioCannotOpen')}</Text>}
      {error && <Text as="p" size="subheadline" tone="danger" role="alert">{error}</Text>}
    </div>
    <footer className="audio-footer">
      <div className="audio-actions"><Button disabled={busy || !selections.length} onClick={() => { pause(); setSelections([]); setSelected(null); setError(''); }}>{t('crop.reset')}</Button>
        <Button variant="primary" disabled={busy || !selections.length} onClick={save}>{saving ? t('crop.working') : t('redact.saveCopy')}</Button></div>
      {waveform && <div className="audio-playbar">
          <Button className="video-play-button" aria-label={playing || starting ? t('crop.pause') : t('redact.audioPlay')}
            disabled={busy} onClick={play}>{playing || starting ? <PauseIcon aria-hidden="true" /> : <PlayIcon aria-hidden="true" />}</Button>
          <input className="audio-seek" type="range" min="0" max={waveform.duration} step="0.01" value={time} disabled={busy}
            aria-label={t('redact.audioSeek')} aria-valuetext={audioTime(time, true)} onChange={event => seek(Number(event.currentTarget.value))} />
          <Text size="caption" tone="secondary" className="audio-time">{audioTime(time)} / {audioTime(waveform.duration)}</Text>
      </div>}
    </footer>
  </main>;
}

function message(error: unknown) { return error instanceof Error ? error.message : String(error); }
