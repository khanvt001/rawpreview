import React from 'react';
import {interpolate, useCurrentFrame, useVideoConfig} from 'remotion';
import {Sfx, clipFrame} from '../audio';
import {Ground} from '../components';
import {Camera, ENTER, Readout, Cursor, HOLD, firstZoomAt, LIVE_WIN, LiveTitle, TiltWindow, track, useClipTime, type Rect, type Shot} from '../motion';
import {FPS, sec} from '../tokens';
import type {SceneProps} from './types';

// 02-looks.mp4, played 1.4× from 1.4 s. Times below are clip seconds and
// positions are window points, read from the recording. The clip is cut from
// raw/02-looks-uncut.mp4 without the stretches where the app dropped a hover
// preview back to the original photo; hover previews run 1.97–4.67, then
// Tokyo Neon Night, Adox Silvermax 21 and Adox Color Implosion are applied.
const START = 1.4;
const RATE = 1.4;
const WIN = LIVE_WIN;
export const LOOKS_LIVE_FRAMES = HOLD + Math.round(((11.65 - START) / RATE) * FPS);

const shots: Shot[] = [
  {t: 1.4, zoom: 1},
  {t: firstZoomAt(START, RATE), zoom: 1.75, x: 1130, y: 420},   // the preset grid while hovering
  {t: 4.3, zoom: 1.75, x: 1130, y: 420},
  {t: 4.95, zoom: 1.45, x: 600, y: 420},   // the photo once a look is applied
  {t: 10.75, zoom: 1.45, x: 600, y: 420},
  {t: 11.55, zoom: 1},
];

const cursorPath: [number, number, number][] = [
  [1.4, 600, 780], [1.9, 1200, 250], [2.68, 1056, 380], [3.41, 1200, 380], [4.11, 1056, 540],
  [4.6, 1200, 380], [4.95, 600, 700], [7.33, 1056, 380], [7.68, 600, 700],
  [10.13, 1200, 250], [10.48, 600, 700],
];
const clicks = [4.65, 7.38, 10.18];

// Each look's category label comes from copy.looks.cats, in this order.
const looks = [
  {at: 4.65, until: 7.38, name: 'Tokyo Neon Night'},
  {at: 7.38, until: 10.18, name: 'Adox Silvermax 21'},
  {at: 10.18, until: 99, name: 'Adox Color Implosion'},
];

export const LooksLive: React.FC<SceneProps> = ({f, t: copy}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const t = useClipTime(START, RATE);
  const zoom = track(t, shots.map((s) => [s.t, s.zoom]));
  // "451" counts up as the headline lands.
  const n = Math.round(interpolate(frame, [ENTER + sec(0.13), ENTER + fps * 0.9], [0, 451], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}));
  const title = copy.looks.title.replace('451', String(n));
  const at = clipFrame(HOLD, START, RATE);
  return (
    <Ground>
      <Camera t={t} win={WIN} shots={shots}>
        <TiltWindow clip="02-looks.mp4" win={WIN} startFrom={START} rate={RATE} />
        <Cursor t={t} win={WIN} path={cursorPath} clicks={clicks} />
      </Camera>
      <LiveTitle f={f} step={copy.looks.step} title={title} caption={copy.looks.caption} zoom={zoom} />
      <Sfx at={at(1.4)} kind="whoosh" volume={0.7} />
      <Sfx at={at(4.3)} kind="whoosh" volume={0.5} />
      <Sfx at={at(10.75)} kind="whoosh" volume={0.6} />
      {clicks.map((c) => <Sfx key={c} at={at(c)} kind="click" />)}
      {looks.map((l) => <Sfx key={l.name} at={at(l.at + 0.08)} kind="pop" volume={0.6} />)}
      {looks.map((l, i) => <Readout key={l.name} f={f} time={t} at={l.at} until={l.until} title={l.name} label={copy.looks.cats[i]} />)}
    </Ground>
  );
};
