import React from 'react';
import {Sfx, clipFrame} from '../audio';
import {Ground} from '../components';
import {Camera, Readout, HOLD, firstZoomAt, LIVE_WIN, LiveTitle, TiltWindow, track, useClipTime, type Shot} from '../motion';
import {FPS} from '../tokens';
import type {SceneProps} from './types';

// 01-preview.mp4, played 1.5× from 0.8 s. Clip seconds and window points:
// the card mounts at 1.5 and the grid fills by 3.5. The scene ends soon after;
// nothing new happens in the grid until the arrow keys at 12.5.
const START = 0.8;
const RATE = 1.5;
const WIN = LIVE_WIN;
export const PREVIEW_LIVE_FRAMES = HOLD + Math.round(((7.0 - START) / RATE) * FPS);

const shots: Shot[] = [
  {t: 0.8, zoom: 1},
  {t: firstZoomAt(START, RATE), zoom: 2.2, x: 150, y: 110},   // the sidebar, as the card appears
  {t: 2.6, zoom: 2.2, x: 150, y: 110},
  {t: 3.8, zoom: 1},                        // the grid filling in
];

export const PreviewLive: React.FC<SceneProps> = ({f, t: copy}) => {
  const t = useClipTime(START, RATE);
  const zoom = track(t, shots.map((s) => [s.t, s.zoom]));
  const c = copy.preview;
  const at = clipFrame(HOLD, START, RATE);
  return (
    <Ground>
      <Camera t={t} win={WIN} shots={shots}>
        <TiltWindow clip="01-preview.mp4" win={WIN} startFrom={START} rate={RATE} />
      </Camera>
      <LiveTitle f={f} step={c.step} title={c.title} caption={c.caption} zoom={zoom} />
      <Sfx at={at(0.8)} kind="whoosh" volume={0.7} />
      <Sfx at={at(2.6)} kind="whoosh" volume={0.6} />
      <Sfx at={at(1.6)} kind="pop" />
      <Sfx at={at(4.0)} kind="pop" />
      <Readout f={f} time={t} at={1.6} until={3.0} title={c.card} label={c.cardLabel} />
      <Readout f={f} time={t} at={4.0} until={7.0} title={c.stat} label={c.statLabel} />
    </Ground>
  );
};
