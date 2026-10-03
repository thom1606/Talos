import { useMemo, useRef, useState, type PointerEvent } from 'react';
import { t } from '@thom1606/talos-sdk/react';
import { audioTime, maximumRanges, type AudioRange, type AudioWaveform } from '../audio';

export type AudioSelection = AudioRange & { id: string };
type Drag = { id: string; mode: 'draw' | 'move' | 'start' | 'end'; origin: number; range: AudioRange; before: AudioSelection[] };

export function AudioWaveformView({ waveform, selections, selected, time, disabled, onSelect, onChange, onSeek, onEdit, onZoom }: {
  waveform: AudioWaveform; selections: AudioSelection[]; selected: string | null; time: number; disabled: boolean;
  onSelect(id: string | null): void; onChange(ranges: AudioSelection[]): void; onSeek(time: number): void; onEdit(): void;
  onZoom(factor: number, center: number): void;
}) {
  const surface = useRef<HTMLDivElement>(null);
  const drag = useRef<Drag | null>(null);
  const [draft, setDraft] = useState<AudioSelection[] | null>(null);
  const span = waveform.end - waveform.start;
  const minimum = Math.min(0.01, span / 100);
  const shown = draft ?? selections;
  const bars = useMemo(() => {
    const count = 160;
    return Array.from({ length: count }, (_, index) => {
      const from = Math.floor(index * waveform.peaks.length / count);
      const to = Math.max(from + 1, Math.floor((index + 1) * waveform.peaks.length / count));
      const peak = Math.max(0, ...waveform.peaks.slice(from, to));
      // A square root makes quiet speech readable without normalizing silence into noise.
      return Math.max(0.8, Math.sqrt(peak) * 72);
    });
  }, [waveform]);
  const percent = (value: number) => (value - waveform.start) / span * 100;
  function point(event: PointerEvent<HTMLDivElement>) {
    const rect = surface.current!.getBoundingClientRect();
    return Math.max(waveform.start, Math.min(waveform.end, waveform.start + (event.clientX - rect.left) / rect.width * span));
  }
  function begin(event: PointerEvent<HTMLDivElement>) {
    if (disabled || event.button !== 0) return;
    const target = event.target as HTMLElement;
    const block = target.closest<HTMLElement>('[data-selection]');
    const range = selections.find(range => range.id === block?.dataset.selection);
    if (!range && selections.length >= maximumRanges) return;
    event.preventDefault(); surface.current!.focus(); event.currentTarget.setPointerCapture(event.pointerId);
    onEdit();
    const origin = point(event);
    const id = range?.id ?? crypto.randomUUID();
    onSelect(id);
    drag.current = { id, mode: range ? (target.dataset.edge as 'start' | 'end' | undefined) ?? 'move' : 'draw', origin,
      range: range ?? { start: origin, end: origin }, before: selections };
  }
  function move(event: PointerEvent<HTMLDivElement>) {
    const current = drag.current;
    if (!current) return;
    const value = point(event), delta = value - current.origin;
    let { start, end } = current.range;
    if (current.mode === 'draw') { start = Math.min(current.origin, value); end = Math.max(current.origin, value); }
    else if (current.mode === 'start') start = Math.max(0, Math.min(end - minimum, value));
    else if (current.mode === 'end') end = Math.min(waveform.duration, Math.max(start + minimum, value));
    else {
      const length = end - start;
      start = Math.max(0, Math.min(waveform.duration - length, start + delta)); end = start + length;
    }
    const next = { id: current.id, start, end };
    setDraft(current.mode === 'draw' ? [...current.before, next] : current.before.map(range => range.id === next.id ? next : range));
  }
  function finish() {
    const current = drag.current;
    if (!current) return;
    if (draft && draft.some(range => range.id === current.id && range.end - range.start >= minimum)) onChange(draft);
    else if (current.mode === 'draw') { onSeek(current.origin); onSelect(null); }
    setDraft(null); drag.current = null;
  }
  return <div className="audio-waveform" ref={surface} role="group" tabIndex={0} aria-label={t('redact.audioWaveform')}
    aria-disabled={disabled} onPointerDown={begin} onPointerMove={move} onPointerUp={finish}
    onPointerCancel={() => { drag.current = null; setDraft(null); }} onLostPointerCapture={finish}
    onKeyDown={event => {
      if (!disabled && ['+', '=', '-'].includes(event.key)) {
        event.preventDefault(); onZoom(event.key === '-' ? 2 : 0.5, (waveform.start + waveform.end) / 2); return;
      }
      if (disabled || !['Backspace', 'Delete', 'ArrowLeft', 'ArrowRight'].includes(event.key)) return;
      event.preventDefault(); onEdit();
      const range = selections.find(range => range.id === selected);
      if (event.key === 'Backspace' || event.key === 'Delete') {
        if (range) { onChange(selections.filter(item => item.id !== selected)); onSelect(null); }
      } else {
        const step = (event.shiftKey ? 1 : 0.1) * (event.key === 'ArrowLeft' ? -1 : 1);
        if (range) {
          const start = Math.max(0, Math.min(waveform.duration - (range.end - range.start), range.start + step));
          onChange(selections.map(item => item.id === selected ? { ...item, start, end: start + range.end - range.start } : item));
        } else onSeek(Math.max(0, Math.min(waveform.duration, time + step)));
      }
    }}>
    <svg viewBox="0 0 480 180" preserveAspectRatio="none" aria-hidden="true">
      <line x1="0" y1="90" x2="480" y2="90" className="audio-baseline" />
      {bars.map((height, index) => <line key={index} x1={index * 3 + 1.5} x2={index * 3 + 1.5} y1={90 - height} y2={90 + height} />)}
    </svg>
    {shown.filter(range => range.end >= waveform.start && range.start <= waveform.end).map((range, index) => {
      const left = Math.max(0, percent(range.start)), right = Math.min(100, percent(range.end));
      return <div key={range.id} className={`audio-selection${selected === range.id ? ' selected' : ''}`} data-selection={range.id}
        role="button" tabIndex={disabled ? -1 : 0} aria-pressed={selected === range.id}
        aria-label={t('redact.audioSelection', { number: index + 1, start: audioTime(range.start, true), end: audioTime(range.end, true) })}
        style={{ left: `${left}%`, width: `${right - left}%` }} onFocus={() => onSelect(range.id)}
        onKeyDown={event => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onSelect(range.id); } }}>
        {selected === range.id && <>
          {range.start >= waveform.start && ['nw', 'w', 'sw'].map(handle => <span key={handle} className={`handle audio-handle ${handle}`} data-edge="start" aria-hidden="true" />)}
          {range.end <= waveform.end && ['ne', 'e', 'se'].map(handle => <span key={handle} className={`handle audio-handle ${handle}`} data-edge="end" aria-hidden="true" />)}
        </>}
      </div>;
    })}
    {time >= waveform.start && time <= waveform.end && <div className="audio-playhead" style={{ left: `${percent(time)}%` }} aria-hidden="true" />}
  </div>;
}
