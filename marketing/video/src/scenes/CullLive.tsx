import React from 'react';
import {interpolate, spring, useVideoConfig} from 'remotion';
import {Sfx, clipFrame} from '../audio';
import {Ground} from '../components';
import {
  Camera, HOLD, firstZoomAt, LIVE_WIN, Cursor, KeyPop, LiveTitle, TiltWindow, toCanvas, track, useClipTime, type Rect, type Shot,
} from '../motion';
import {FPS, color} from '../tokens';
import type {SceneProps} from './types';

// 03-cull.mp4, played 1.4× from 0.2 s. Clip seconds and window points.
const START = 0.2;
const RATE = 1.4;
const WIN = LIVE_WIN;
export const CULL_LIVE_FRAMES = HOLD + Math.round(((12.05 - START) / RATE) * FPS);

// Thumbnail centres in the grid, and where each one's check badge appears.
const photo = {
  p6775: {x: 339, y: 195, check: {x: 422, y: 113}},
  p6773: {x: 753, y: 195, check: {x: 836, y: 113}},
  p6766: {x: 1168, y: 400, check: {x: 1251, y: 318}},
  p6762: {x: 960, y: 610, check: {x: 1043, y: 528}},
};

const shots: Shot[] = [
  {t: 0.2, zoom: 1},
  {t: firstZoomAt(START, RATE), zoom: 1.9, ...photo.p6775},
  {t: 3.3, zoom: 1.9, ...photo.p6775},
  {t: 3.75, zoom: 1.9, ...photo.p6773},
  {t: 5.3, zoom: 1.9, ...photo.p6773},
  {t: 5.8, zoom: 1.9, ...photo.p6766},
  {t: 8.35, zoom: 1.9, ...photo.p6766},
  {t: 8.85, zoom: 1.9, ...photo.p6762},
  {t: 10.9, zoom: 1.9, ...photo.p6762},
  {t: 11.8, zoom: 1},
];

const cursorPath: [number, number, number][] = [
  [0.2, 700, 845], [0.53, 339, 230], [3.6, 753, 230], [5.63, 1168, 435], [8.7, 960, 645],
];
const clicks = [0.53, 3.6, 5.63, 8.7];

const keys = [
  {at: 1.25, label: '5', ...photo.p6775},
  {at: 2.4, label: 'S', ...photo.p6775},
  {at: 4.3, label: '4', ...photo.p6773},
  {at: 6.33, label: '5', ...photo.p6766},
  {at: 7.5, label: 'S', ...photo.p6766},
  {at: 9.4, label: '4', ...photo.p6762},
  {at: 10.6, label: 'S', ...photo.p6762},
];

// A green ring bursting from the app's own check badge when a photo is marked.
const MarkBurst: React.FC<{t: number; at: number; x: number; y: number}> = ({t, at, x, y}) => {
  const {fps} = useVideoConfig();
  const local = t - at;
  if (local < 0 || local > 0.9) return null;
  const p = toCanvas(WIN, x, y);
  const s = spring({frame: local * fps, fps, config: {damping: 12, mass: 0.5}});
  const ring = interpolate(local, [0, 0.6], [0.4, 2.4], {extrapolateRight: 'clamp'});
  return (
    <>
      <div style={{position: 'absolute', left: p.x - 22, top: p.y - 22, width: 44, height: 44, borderRadius: '50%',
        border: `3px solid ${color.check}`, transform: `scale(${ring})`,
        opacity: interpolate(local, [0.2, 0.6], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}} />
      <div style={{position: 'absolute', left: p.x - 18, top: p.y - 18, width: 36, height: 36, borderRadius: '50%',
        background: color.check, transform: `scale(${s * 1.3})`, opacity: interpolate(local, [0.6, 0.9], [1, 0], {extrapolateLeft: 'clamp'})}} />
    </>
  );
};

export const CullLive: React.FC<SceneProps> = ({f, t: copy}) => {
  const t = useClipTime(START, RATE);
  const zoom = track(t, shots.map((s) => [s.t, s.zoom]));
  const at = clipFrame(HOLD, START, RATE);
  return (
    <Ground>
      <Sfx at={at(0.2)} kind="whoosh" volume={0.7} />
      {[3.3, 5.3, 8.35].map((p) => <Sfx key={p} at={at(p)} kind="whoosh" volume={0.35} />)}
      <Sfx at={at(10.9)} kind="whoosh" volume={0.6} />
      {clicks.map((c) => <Sfx key={c} at={at(c)} kind="click" />)}
      {keys.map((k) => <Sfx key={k.at} at={at(k.at)} kind="pop" />)}
      <Camera t={t} win={WIN} shots={shots}>
        <TiltWindow clip="03-cull.mp4" win={WIN} startFrom={START} rate={RATE} />
        {keys.filter((k) => k.label === 'S').map((k) => <MarkBurst key={k.at} t={t} at={k.at} {...k.check} />)}
        {keys.map((k) => (
          <KeyPop key={k.at} f={f} t={t} at={k.at} win={WIN} x={k.x - 70} y={k.y - 40} label={k.label} />
        ))}
        <Cursor t={t} win={WIN} path={cursorPath} clicks={clicks} />
      </Camera>
      <LiveTitle f={f} step={copy.cull.step} title={copy.cull.title} caption={copy.cull.caption} zoom={zoom} />
    </Ground>
  );
};
