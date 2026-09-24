import { useEffect, useMemo, useRef, useState, type PointerEvent } from 'react';
import { talosWindow } from '@thom1606/talos-sdk/window';
import { PauseIcon, PlayIcon } from '@radix-ui/react-icons';
import { Button, Text, t, useTalos, type TalosFile } from '@thom1606/talos-sdk/react';
import { fitCrop, moveCrop, pixelCrop, resizeCrop, type Handle, type Rect } from './crop-geometry';
import { mediaKind } from '../media';
import './crop.css';

const ratios = [['Free', null], ['1:1', 1], ['16:9', 16 / 9], ['9:16', 9 / 16], ['4:3', 4 / 3], ['3:4', 3 / 4]] as const;
const handles: Handle[] = ['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w'];
type CropImage = { name: string; dataURL: string; width: number; height: number; video: boolean };
type Drag = { start: Rect; clientX: number; clientY: number; scale: number; handle: Handle | 'move' };

export default function CropWindow() {
  const { files } = useTalos();
  const images = useMemo(() => files.filter(file => ['image', 'video'].includes(mediaKind(file.name) ?? '')), [files]);
  const [selectedPath, setSelectedPath] = useState(images[0]?.path ?? '');
  const [image, setImage] = useState<CropImage | null>(null);
  const [crop, setCrop] = useState<Rect>({ x: 0, y: 0, width: 1, height: 1 });
  const [ratio, setRatio] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [videoTime, setVideoTime] = useState(0);
  const [videoDuration, setVideoDuration] = useState(0);
  const [videoPlaying, setVideoPlaying] = useState(false);
  const [videoReady, setVideoReady] = useState(false);
  const [videoPoster, setVideoPoster] = useState<string | null>(null);
  const [showVideoPoster, setShowVideoPoster] = useState(false);
  const [stageSize, setStageSize] = useState({ width: 400, height: 400 });
  const stage = useRef<HTMLDivElement>(null);
  const photo = useRef<HTMLImageElement>(null);
  const drag = useRef<Drag | null>(null);
  const video = useRef<HTMLVideoElement>(null);
  const primingVideo = useRef(false);

  useEffect(() => {
    const observer = new ResizeObserver(([entry]) => setStageSize({ width: entry.contentRect.width, height: entry.contentRect.height }));
    if (stage.current) observer.observe(stage.current);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    const file = images.find(file => file.path === selectedPath);
    let cancelled = false;
    let previewURL: string | undefined;
    setImage(null); setError(''); setVideoTime(0); setVideoDuration(0); setVideoPlaying(false); setVideoReady(false);
    setVideoPoster(null); setShowVideoPoster(false); primingVideo.current = false;
    if (!file) { setBusy(false); return; }
    setBusy(true);
    loadImage(file).then(next => {
      previewURL = next.dataURL;
      if (cancelled) { URL.revokeObjectURL(next.dataURL); return; }
      setImage(next); setRatio(null); setCrop(fitCrop(next, null));
    }).catch((error: Error) => { if (!cancelled) setError(error.message); })
      .finally(() => { if (!cancelled) setBusy(false); });
    return () => { cancelled = true; if (previewURL) URL.revokeObjectURL(previewURL); };
  }, [images, selectedPath]);

  function startDrag(event: PointerEvent<HTMLDivElement>) {
    if (!image || busy || event.button !== 0) return;
    event.preventDefault(); event.currentTarget.setPointerCapture(event.pointerId);
    const handle = (event.target as HTMLElement).dataset.handle as Handle | undefined;
    drag.current = { start: crop, clientX: event.clientX, clientY: event.clientY,
      scale: event.currentTarget.getBoundingClientRect().width / crop.width, handle: handle ?? 'move' };
  }
  function updateDrag(event: PointerEvent<HTMLDivElement>) {
    const current = drag.current;
    if (!current || !image) return;
    const dx = (event.clientX - current.clientX) / current.scale;
    const dy = (event.clientY - current.clientY) / current.scale;
    setCrop(current.handle === 'move' ? moveCrop(current.start, dx, dy, image)
      : resizeCrop(current.start, current.handle, dx, dy, image, ratio));
  }
  function changeDimension(axis: 'width' | 'height', value: number) {
    if (!image || !Number.isFinite(value) || value < 1) return;
    setCrop(resizeCrop(crop, axis === 'width' ? 'e' : 's', axis === 'width' ? value - crop.width : 0,
      axis === 'height' ? value - crop.height : 0, image, ratio));
  }
  async function save() {
    if (!image || (!image.video && (!photo.current?.complete || !photo.current.naturalWidth))) return;
    setBusy(true); setError('');
    try {
      const rect = outputCrop(crop, image);
      if (image.video) {
        await talosWindow.invoke<string>('cropVideo', { index: files.findIndex(file => file.path === selectedPath), rect });
        await talosWindow.close();
        return;
      }
      await talosWindow.invoke<string>('cropImage', { index: files.findIndex(file => file.path === selectedPath), rect });
      await talosWindow.close();
    } catch (e) { setError(String(e instanceof Error ? e.message : e)); }
    finally { setBusy(false); }
  }
  const scale = image ? Math.min((stageSize.width - 24) / image.width, (stageSize.height - 24) / image.height, 1) : 1;
  const pixels = image ? outputCrop(crop, image) : crop;
  return <main aria-busy={busy}>
    {images.length > 1 && <div className="filebar"><select aria-label={t('crop.chooseImage')} value={selectedPath} disabled={busy}
        onChange={event => setSelectedPath(event.currentTarget.value)}>
        {images.map(file => <option key={file.path} value={file.path}>{file.name}</option>)}
      </select></div>}
    <div className="stage" ref={stage}>
      {image ? <div className="image-frame" style={{ width: image.width * scale, height: image.height * scale }}>
        {image.video ? <video ref={video} src={image.dataURL} muted loop playsInline preload="metadata" aria-label={image.name}
          onLoadedMetadata={event => {
            const element = event.currentTarget;
            const duration = element.duration;
            setVideoDuration(Number.isFinite(duration) ? duration : 0);
            primingVideo.current = true;
            showFirstVideoFrame(element).then(poster => {
              if (element.isConnected) {
                primingVideo.current = false; setVideoTime(element.currentTime);
                setVideoPoster(poster); setShowVideoPoster(true); setVideoReady(true);
              }
            }).catch(() => { if (element.isConnected) { primingVideo.current = false; setVideoReady(true); setError(t('crop.videoError')); } });
          }}
          onTimeUpdate={event => setVideoTime(event.currentTarget.currentTime)}
          onSeeked={event => setVideoTime(event.currentTarget.currentTime)}
          onPlay={() => { if (!primingVideo.current) { setShowVideoPoster(false); setVideoPlaying(true); } }} onPause={() => setVideoPlaying(false)}
          onError={() => setError(t('crop.videoError'))} /> : <img ref={photo} src={image.dataURL} alt={image.name} draggable={false} />}
        {image.video && videoPoster && showVideoPoster && <img className="video-poster" src={videoPoster} alt="" draggable={false} />}
        <svg className="shade" viewBox={`0 0 ${image.width} ${image.height}`} aria-hidden="true">
          <path fillRule="evenodd" d={`M0 0H${image.width}V${image.height}H0Z M${crop.x} ${crop.y}h${crop.width}v${crop.height}h${-crop.width}Z`} />
        </svg>
        <div className="crop-selection" role="group" aria-label={t('crop.selectionHelp')} tabIndex={0}
          style={{ left: crop.x * scale, top: crop.y * scale, width: crop.width * scale, height: crop.height * scale }}
          onPointerDown={startDrag} onPointerMove={updateDrag}
          onPointerUp={() => { drag.current = null; }} onPointerCancel={() => { drag.current = null; }}
          onLostPointerCapture={() => { drag.current = null; }}
          onKeyDown={(event) => {
            if (busy || !['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(event.key)) return;
            event.preventDefault(); const step = event.shiftKey ? 10 : 1;
            setCrop(moveCrop(crop, event.key === 'ArrowLeft' ? -step : event.key === 'ArrowRight' ? step : 0,
              event.key === 'ArrowUp' ? -step : event.key === 'ArrowDown' ? step : 0, image));
          }}>
          <div className="grid" aria-hidden="true"><i /><i /><i /><i /></div>
          {handles.map(handle => <span key={handle} className={`handle ${handle}`} data-handle={handle} aria-hidden="true" />)}
        </div>
      </div> : <div className="empty"><svg viewBox="0 0 48 48" aria-hidden="true"><path d="M12 5v31h31M5 12h31v31M20 5v7M5 20h7M36 28h7M28 36v7" /></svg>
        <Text as="p" size="headline" tone="secondary">{busy ? t('crop.opening') : t('crop.emptyTitle')}</Text>
        <Text as="p" tone="secondary">{t('crop.noInput')}</Text></div>}
    </div>
    <section className="controls" aria-label={t('crop.options')}>
      {image?.video && !videoReady && <Text as="p" size="caption" tone="secondary">{t('crop.opening')}</Text>}
      {image?.video && videoReady && <div className="video-controls"><Button className="video-play-button" aria-label={videoPlaying ? t('crop.pause') : t('crop.play')} disabled={busy} onClick={() => {
        if (video.current?.paused) void video.current.play().catch(() => setError(t('crop.videoError')));
        else video.current?.pause();
      }}>{videoPlaying ? <PauseIcon aria-hidden="true" /> : <PlayIcon aria-hidden="true" />}</Button>
        <input className="video-seek" type="range" min="0" max={videoDuration || 1} step="0.01" value={Math.min(videoTime, videoDuration || 1)}
          aria-label={t('crop.seek')} aria-valuetext={formatTime(videoTime)} disabled={busy || !videoDuration}
          onChange={event => { const time = Number(event.currentTarget.value); setShowVideoPoster(false); if (video.current) video.current.currentTime = time; setVideoTime(time); }} />
        <Text as="span" size="caption" tone="secondary" className="video-time">{formatTime(videoTime)} / {formatTime(videoDuration)}</Text>
      </div>}
      <div className="option-row"><Text size="callout" textKey="crop.aspectRatio" /><div className="talos-segments" role="group" aria-label={t('crop.aspectRatio')}>
        {ratios.map(([name, value]) => <Button key={name} aria-pressed={ratio === value} disabled={!image || busy}
          onClick={() => { setRatio(value); if (image) setCrop(fitCrop(image, value)); }}>{name === 'Free' ? t('crop.free') : name}</Button>)}
      </div></div>
      <div className="dimensions">
        <Dimension label={t('crop.widthShort')} value={pixels.width} max={image?.width ?? 1} disabled={!image || busy} onChange={value => changeDimension('width', value)} />
        <Dimension label={t('crop.heightShort')} value={pixels.height} max={image?.height ?? 1} disabled={!image || busy} onChange={value => changeDimension('height', value)} />
      </div>
      {error && <Text as="p" size="subheadline" tone="danger" className="message" role="alert">{error}</Text>}
    </section>
    <footer><Button disabled={!image || busy} onClick={() => { if (image) setCrop(fitCrop(image, null)); setRatio(null); setError(''); }}>{t('crop.reset')}</Button>
      <Button variant="primary" disabled={!image || busy || (image.video && !videoReady)} onClick={save}>{busy ? t('crop.working') : t('crop.saveCopy')}</Button></footer>
  </main>;
}

async function showFirstVideoFrame(element: HTMLVideoElement): Promise<string> {
  const frame = new Promise<string>((resolve, reject) => element.requestVideoFrameCallback(() => {
    try {
      const canvas = document.createElement('canvas');
      const scale = Math.min(1, 1280 / Math.max(element.videoWidth, element.videoHeight));
      canvas.width = Math.round(element.videoWidth * scale);
      canvas.height = Math.round(element.videoHeight * scale);
      const context = canvas.getContext('2d');
      if (!context) throw new Error('Cannot capture video frame');
      context.drawImage(element, 0, 0, canvas.width, canvas.height);
      resolve(canvas.toDataURL('image/jpeg', 0.9));
    } catch (error) { reject(error); }
  }));
  try {
    await element.play();
    return await frame;
  } finally {
    element.pause();
  }
}


// Image decoding, supported formats and export encoding belong to this crop tool.
async function loadImage(input: TalosFile): Promise<CropImage> {
  const dataURL = talosWindow.fileURL(input);
  if (mediaKind(input.name) === 'video') {
    if (!/\.(mp4|mov|m4v)$/i.test(input.name)) throw new Error(t('crop.videoUnsupported'));
    return new Promise((resolve, reject) => {
      const video = document.createElement('video');
      const timer = setTimeout(() => finish(new Error(t('crop.videoError'))), 15_000);
      function finish(error?: Error) {
        clearTimeout(timer); video.onloadedmetadata = null; video.onerror = null;
        const width = video.videoWidth, height = video.videoHeight;
        video.removeAttribute('src'); video.load();
        if (error || !width || !height) reject(error ?? new Error(t('crop.videoError')));
        else resolve({ name: input.name, dataURL, width, height, video: true });
      }
      video.onloadedmetadata = () => finish();
      video.onerror = () => finish(new Error(t('crop.videoError')));
      video.preload = 'metadata'; video.src = dataURL;
    });
  }
  const decoded = new Image(); decoded.src = dataURL;
  await decoded.decode();
  const width = decoded.naturalWidth, height = decoded.naturalHeight;
  if (!width || !height) throw new Error(t('crop.cannotOpen'));
  return { name: input.name, dataURL, width, height, video: false };
}

function Dimension({ label, value, max, disabled, onChange }: {
  label: string; value: number; max: number; disabled: boolean; onChange(value: number): void;
}) {
  const [draft, setDraft] = useState(String(value));
  useEffect(() => setDraft(String(value)), [value]);
  function commit() {
    const parsed = Number(draft);
    if (draft.trim() && Number.isFinite(parsed)) onChange(Math.max(1, Math.min(max, Math.round(parsed))));
    setDraft(String(value));
  }
  return <label><Text size="callout">{label}</Text><div className="dimension-input"><input aria-label={label} type="number"
    min="1" max={max} value={draft} disabled={disabled} onChange={event => setDraft(event.currentTarget.value)}
    onBlur={commit} onKeyDown={event => { if (event.key === 'Enter') event.currentTarget.blur(); }} /><Text size="caption" tone="secondary">px</Text></div></label>;
}

// 4:2:0 video encoders require even dimensions. Display exactly the dimensions we export.
function outputCrop(crop: Rect, image: CropImage): Rect {
  const rect = pixelCrop(crop, image);
  return image.video ? { ...rect, width: Math.max(2, Math.floor(rect.width / 2) * 2), height: Math.max(2, Math.floor(rect.height / 2) * 2) } : rect;
}

function formatTime(seconds: number): string {
  if (!Number.isFinite(seconds)) return '0:00';
  const whole = Math.floor(seconds);
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`;
}
