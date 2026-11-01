import React from 'react';
import {Sfx, clipFrame} from '../audio';
import {Ground} from '../components';
import {
  Camera, Cursor, HOLD, firstZoomAt, LIVE_WIN, LiveTitle, Readout, TiltWindow, toCanvas, track, useClipTime, type Shot,
} from '../motion';
import {FPS} from '../tokens';
import type {SceneProps} from './types';

// 05-airdrop.mp4, played 1.3× from 0.6 s. Clip seconds and window points:
// the Copy menu opens at 1.3, With "Tokyo Neon Night" at 2.3, AirDrop at 3.75,
// the AirDrop panel appears at 4.5, Iphone 14 at 7.2, "Sent" at 11.0.
const START = 0.6;
const RATE = 1.3;
const WIN = LIVE_WIN;
export const SHARE_LIVE_FRAMES = HOLD + Math.round(((13.5 - START) / RATE) * FPS);

const shots: Shot[] = [
  {t: 0.6, zoom: 1},
  {t: firstZoomAt(START, RATE), zoom: 1.8, x: 760, y: 730},   // the Copy menu and its submenu
  {t: 4.0, zoom: 1.8, x: 760, y: 730},
  {t: 4.7, zoom: 1.9, x: 640, y: 458},     // the AirDrop panel
  {t: 12.2, zoom: 1.9, x: 640, y: 458},
  {t: 13.3, zoom: 1},
];

const cursorPath: [number, number, number][] = [
  [0.6, 700, 780], [1.3, 627, 843], [2.3, 700, 785], [3.55, 880, 785], [3.75, 900, 807], [7.2, 501, 423], [7.7, 610, 520],
];
const clicks = [1.3, 3.75, 7.2];

// The panel shows the sender's avatar and name; keep them out of the video.
const SenderBlur: React.FC<{t: number}> = ({t}) => {
  if (t < 4.4) return null;
  const a = toCanvas(WIN, 466, 336);
  const b = toCanvas(WIN, 600, 386);
  return (
    <div style={{position: 'absolute', left: a.x, top: a.y, width: b.x - a.x, height: b.y - a.y,
      borderRadius: 8, backdropFilter: 'blur(9px)', WebkitBackdropFilter: 'blur(9px)'}} />
  );
};

export const ShareLive: React.FC<SceneProps> = ({f, t: copy}) => {
  const t = useClipTime(START, RATE);
  const zoom = track(t, shots.map((s) => [s.t, s.zoom]));
  const c = copy.share;
  const at = clipFrame(HOLD, START, RATE);
  return (
    <Ground>
      <Sfx at={at(0.6)} kind="whoosh" volume={0.7} />
      <Sfx at={at(4.0)} kind="whoosh" volume={0.5} />
      <Sfx at={at(12.2)} kind="whoosh" volume={0.6} />
      {clicks.map((x) => <Sfx key={x} at={at(x)} kind="click" />)}
      <Sfx at={at(4.6)} kind="pop" volume={0.6} />
      <Sfx at={at(11.0)} kind="pop" />
      <Camera t={t} win={WIN} shots={shots}>
        <TiltWindow clip="05-airdrop.mp4" win={WIN} startFrom={START} rate={RATE} />
        <SenderBlur t={t} />
        <Cursor t={t} win={WIN} path={cursorPath} clicks={clicks} />
      </Camera>
      <LiveTitle f={f} step={c.step} title={c.title} caption={c.caption} zoom={zoom} />
      <Readout f={f} time={t} at={4.6} until={7.6} title={c.sending} label={c.sendingLabel} />
      <Readout f={f} time={t} at={11.0} until={13.5} title={c.sent} label={c.sentLabel} />
    </Ground>
  );
};
