export type Rect = { x: number; y: number; width: number; height: number };
export type Size = { width: number; height: number };
export type Handle = 'n' | 's' | 'e' | 'w' | 'nw' | 'ne' | 'sw' | 'se';
export const clamp = (n: number, min: number, max: number) => Math.min(max, Math.max(min, n));

export function fitCrop(size: Size, ratio: number | null): Rect {
  const width = ratio ? Math.min(size.width, size.height * ratio) : size.width;
  const height = ratio ? width / ratio : size.height;
  return { x: (size.width - width) / 2, y: (size.height - height) / 2, width, height };
}

export function moveCrop(rect: Rect, dx: number, dy: number, size: Size): Rect {
  return { ...rect, x: clamp(rect.x + dx, 0, size.width - rect.width), y: clamp(rect.y + dy, 0, size.height - rect.height) };
}

export function resizeCrop(rect: Rect, handle: Handle, dx: number, dy: number, size: Size, ratio: number | null): Rect {
  const west = handle.includes('w'), east = handle.includes('e');
  const north = handle.includes('n'), south = handle.includes('s');
  let x = west ? clamp(rect.x + dx, 0, rect.x + rect.width - 1) : rect.x;
  let y = north ? clamp(rect.y + dy, 0, rect.y + rect.height - 1) : rect.y;
  let width = east ? clamp(rect.width + dx, 1, size.width - x) : rect.x + rect.width - x;
  let height = south ? clamp(rect.height + dy, 1, size.height - y) : rect.y + rect.height - y;
  if (!ratio) return { x, y, width, height };
  const anchorX = west ? rect.x + rect.width : rect.x;
  const anchorY = north ? rect.y + rect.height : rect.y;
  const centerX = rect.x + rect.width / 2, centerY = rect.y + rect.height / 2;
  if ((west || east) && (north || south)) {
    width = Math.abs(dx) >= Math.abs(dy * ratio) ? width : height * ratio;
    const maxWidth = Math.min(west ? anchorX : size.width - anchorX, (north ? anchorY : size.height - anchorY) * ratio);
    width = clamp(width, Math.max(1, ratio), maxWidth); height = width / ratio;
    x = west ? anchorX - width : anchorX; y = north ? anchorY - height : anchorY;
  } else if (west || east) {
    const maxWidth = Math.min(west ? anchorX : size.width - anchorX, 2 * Math.min(centerY, size.height - centerY) * ratio);
    width = clamp(width, Math.max(1, ratio), maxWidth); height = width / ratio;
    x = west ? anchorX - width : anchorX; y = centerY - height / 2;
  } else {
    const maxHeight = Math.min(north ? anchorY : size.height - anchorY, 2 * Math.min(centerX, size.width - centerX) / ratio);
    height = clamp(height, Math.max(1, 1 / ratio), maxHeight); width = height * ratio;
    y = north ? anchorY - height : anchorY; x = centerX - width / 2;
  }
  return { x, y, width, height };
}

/** Integer bounds used for the output exactly match the pixel dimensions shown in the UI. */
export function pixelCrop(rect: Rect, size: Size): Rect {
  const x = clamp(Math.round(rect.x), 0, size.width - 1);
  const y = clamp(Math.round(rect.y), 0, size.height - 1);
  return { x, y, width: clamp(Math.round(rect.width), 1, size.width - x), height: clamp(Math.round(rect.height), 1, size.height - y) };
}
