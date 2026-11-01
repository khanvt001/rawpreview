import React from 'react';
import {Sfx, clipFrame} from '../audio';
import {Ground} from '../components';
import {
  Camera, Readout, Cursor, HOLD, firstZoomAt, KeyPop, LIVE_WIN, LiveTitle, TiltWindow, track, useClipTime, type Shot,
} from '../motion';
import {FPS} from '../tokens';
import type {SceneProps} from './types';

// 04-copy.mp4, played 1.2× from 0.3 s. Clip seconds and window points:
// ⌘↩ at 1.45, Copy Complete at 2.5, a cut at 5.0, Done at 5.5, Eject at 7.33.
const START = 0.3;
const RATE = 1.2;
const WIN = LIVE_WIN;
export const COPY_LIVE_FRAMES = HOLD + Math.round(((9.9 - START) / RATE) * FPS);

const shots: Shot[] = [
  {t: 0.3, zoom: 1},
  {t: firstZoomAt(START, RATE), zoom: 1.9, x: 520, y: 800},   // the "Copy 3 to …" bar
  {t: 1.7, zoom: 1.9, x: 520, y: 800},
  {t: 2.3, zoom: 1.7, x: 640, y: 430},     // the copy sheet
  {t: 5.7, zoom: 1.7, x: 640, y: 430},
  {t: 6.4, zoom: 2.1, x: 170, y: 110},     // Eject in the sidebar
  {t: 7.9, zoom: 2.1, x: 170, y: 110},
  {t: 8.8, zoom: 1},
];

const cursorPath: [number, number, number][] = [
  [0.3, 980, 700], [5.5, 811, 459], [7.33, 204, 91], [9.9, 204, 91],
];

export const CopyLive: React.FC<SceneProps> = ({f, t: copy}) => {
  const t = useClipTime(START, RATE);
  const zoom = track(t, shots.map((s) => [s.t, s.zoom]));
  const c = copy.copy;
  const at = clipFrame(HOLD, START, RATE);
  return (
    <Ground>
      <Camera t={t} win={WIN} shots={shots}>
        <TiltWindow clip="04-copy.mp4" win={WIN} startFrom={START} rate={RATE} />
        <KeyPop f={f} t={t} at={1.45} win={WIN} x={520} y={770} label="⌘ ↩" />
        <Cursor t={t} win={WIN} path={cursorPath} clicks={[5.5, 7.33]} />
      </Camera>
      <LiveTitle f={f} step={c.step} title={c.title} caption={c.caption} zoom={zoom} />
      <Sfx at={at(0.3)} kind="whoosh" volume={0.7} />
      <Sfx at={at(1.7)} kind="whoosh" volume={0.4} />
      <Sfx at={at(5.7)} kind="whoosh" volume={0.5} />
      <Sfx at={at(7.9)} kind="whoosh" volume={0.6} />
      <Sfx at={at(1.45)} kind="pop" />
      <Sfx at={at(2.6)} kind="pop" volume={0.6} />
      <Sfx at={at(7.8)} kind="pop" volume={0.6} />
      {[5.5, 7.33].map((x) => <Sfx key={x} at={at(x)} kind="click" />)}
      <Readout f={f} time={t} at={2.6} until={5.4} title={c.stat} label={c.statLabel} />
      <Readout f={f} time={t} at={7.8} until={9.9} title={c.eject} label={c.ejectLabel} />
    </Ground>
  );
};
