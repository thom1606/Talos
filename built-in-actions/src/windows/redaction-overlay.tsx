import { useRef, useState, type PointerEvent } from 'react';
import { t } from '@thom1606/talos-sdk/react';
import { clamp, moveCrop, resizeCrop, type Handle, type Rect, type Size } from './crop-geometry';

export type Redaction = { id: string; rect: Rect };
type Drag = { id: string; rect: Rect; x: number; y: number; handle: Handle | 'move' | 'draw'; original: Redaction[] };
const handles: Handle[] = ['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w'];

export function RedactionOverlay({ size, scale, blocks, onChange, disabled }: {
  size: Size; scale: number; blocks: Redaction[]; onChange(blocks: Redaction[]): void; disabled: boolean;
}) {
  const [selected, setSelected] = useState<string | null>(null);
  const drag = useRef<Drag | null>(null);
  const surface = useRef<HTMLDivElement>(null);
  function point(event: PointerEvent<HTMLDivElement>) {
    const bounds = surface.current!.getBoundingClientRect();
    return { x: clamp((event.clientX - bounds.left) / scale, 0, size.width),
      y: clamp((event.clientY - bounds.top) / scale, 0, size.height) };
  }
  function start(event: PointerEvent<HTMLDivElement>, block?: Redaction) {
    if (disabled || event.button !== 0) return;
    event.preventDefault(); event.stopPropagation();
    event.currentTarget.focus(); event.currentTarget.setPointerCapture(event.pointerId);
    const { x, y } = point(event);
    const id = block?.id ?? crypto.randomUUID();
    const rect = block?.rect ?? { x, y, width: 0, height: 0 };
    setSelected(id);
    drag.current = { id, rect, x, y, original: blocks,
      handle: block ? ((event.target as HTMLElement).dataset.handle as Handle | undefined) ?? 'move' : 'draw' };
  }
  function update(event: PointerEvent<HTMLDivElement>) {
    const current = drag.current;
    if (!current || disabled) return;
    const { x, y } = point(event);
    const dx = x - current.x, dy = y - current.y;
    const rect = current.handle === 'draw'
      ? { x: Math.min(x, current.x), y: Math.min(y, current.y), width: Math.abs(dx), height: Math.abs(dy) }
      : current.handle === 'move' ? moveCrop(current.rect, dx, dy, size)
      : resizeCrop(current.rect, current.handle, dx, dy, size, null);
    if (current.handle === 'draw') {
      onChange(rect.width >= 1 && rect.height >= 1 ? [...current.original, { id: current.id, rect }] : current.original);
    } else onChange(current.original.map(block => block.id === current.id ? { ...block, rect } : block));
  }
  return <div ref={surface} className="redaction-surface" tabIndex={0} role="group" aria-label={t('redact.help')}
    onPointerDown={event => start(event)} onPointerMove={update}
    onPointerUp={() => { drag.current = null; }}
    onPointerCancel={() => { if (drag.current) onChange(drag.current.original); drag.current = null; }}
    onLostPointerCapture={() => { drag.current = null; }}
    onKeyDown={event => {
      if (disabled || !selected) return;
      if (event.key === 'Backspace' || event.key === 'Delete') {
        event.preventDefault(); drag.current = null;
        onChange(blocks.filter(block => block.id !== selected)); setSelected(null); surface.current?.focus();
      } else if (event.key === 'Escape') { setSelected(null); surface.current?.focus(); }
      else if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(event.key)) {
        event.preventDefault(); const step = event.shiftKey ? 10 : 1;
        onChange(blocks.map(block => block.id !== selected ? block : { ...block, rect: moveCrop(block.rect,
          event.key === 'ArrowLeft' ? -step : event.key === 'ArrowRight' ? step : 0,
          event.key === 'ArrowUp' ? -step : event.key === 'ArrowDown' ? step : 0, size) }));
      }
    }}>
    {blocks.map((block, index) => <div key={block.id} className={`redaction-block${selected === block.id ? ' selected' : ''}`}
      role="group" tabIndex={0} aria-label={t('redact.block', { number: index + 1 })}
      onFocus={() => setSelected(block.id)} onPointerDown={event => start(event, block)}
      style={{ left: block.rect.x * scale, top: block.rect.y * scale,
        width: block.rect.width * scale, height: block.rect.height * scale }}>
      {selected === block.id && handles.map(handle => <span key={handle} className={`handle ${handle}`} data-handle={handle} aria-hidden="true" />)}
    </div>)}
  </div>;
}
