import { useState } from 'react';
import { Text, t, useTalos } from '@thom1606/talos-sdk/react';
import { mediaKind } from '../media';
import CropWindow from './crop';
import AudioRedactWindow from './redact-audio';

export default function RedactWindow() {
  const { files } = useTalos();
  const inputs = files.filter(file => ['image', 'audio'].includes(mediaKind(file.name) ?? ''));
  const [path, setPath] = useState(inputs[0]?.path ?? '');
  const [busy, setBusy] = useState(false);
  const file = inputs.find(file => file.path === path);
  return <div className="redact-window">
    {inputs.length > 1 && <div className="filebar"><select aria-label={t('redact.chooseFile')} disabled={busy} value={path} onChange={event => setPath(event.currentTarget.value)}>
      {inputs.map(file => <option key={file.path} value={file.path}>{file.name}</option>)}
    </select></div>}
    {file ? mediaKind(file.name) === 'audio'
      ? <AudioRedactWindow key={file.path} index={files.indexOf(file)} onBusyChange={setBusy} />
      : <CropWindow key={file.path} mode="redact" input={file} onBusyChange={setBusy} />
      : <main className="empty"><Text tone="secondary">{t('redact.noInput')}</Text></main>}
  </div>;
}
