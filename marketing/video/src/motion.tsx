import React from 'react';
import {
  AbsoluteFill, Easing, Freeze, OffthreadVideo, Sequence, interpolate, spring, staticFile,
  useCurrentFrame, useVideoConfig,
} from 'remotion';
import {color, radius, sec, shadowWindow} from './tokens';
import type {fonts as fontsFn} from './fonts';

type Fonts = ReturnType<typeof fontsFn>;

// Recordings are a 1280 × 860 pt window captured at 1600 × 1076 px.
const PT = 1.25;
const SRC_W = 1600;
const SRC_H = 1076;

export type Rect = {x: number; y: number; w: number; h: number};

// Where the recording sits on the 1920 × 1080 canvas before the camera moves.
export const LIVE_WIN: Rect = {x: 395, y: 282, w: 1130, h: 760};

// Frames the recording holds still at the start of a scene, while the scene
// fades in, the window swings in and the title lands. Every scene shares it.
export const HOLD = sec(1.6);

// A scene is hidden for the first half of the cut that brings it in, so its
// window and title wait this long before they move.
export const ENTER = sec(0.4);

// Seconds on screen for each scene's first move from the whole window to a
// detail, whatever the scene's playback rate.
export const ZOOM_IN = 0.6;
export const firstZoomAt = (start: number, rate: number) => start + ZOOM_IN * rate;

// Clip time (seconds into the recording) for the current frame.
export const useClipTime = (startFrom: number, rate: number, hold = HOLD) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return startFrom + (Math.max(0, frame - hold) / fps) * rate;
};

// Canvas position of a point given in window points.
export const toCanvas = (win: Rect, x: number, y: number) => ({
  x: win.x + (x * PT * win.w) / SRC_W,
  y: win.y + (y * PT * win.h) / SRC_H,
});

const ease = Easing.bezier(0.65, 0, 0.35, 1);

// Piecewise eased value over clip-time keyframes. Repeat a value to hold it.
export const track = (t: number, keys: [number, number][]) => {
  if (t <= keys[0][0]) return keys[0][1];
  for (let i = 0; i < keys.length - 1; i++) {
    const [t0, v0] = keys[i];
    const [t1, v1] = keys[i + 1];
    if (t <= t1) return interpolate(t, [t0, t1], [v0, v1], {easing: ease});
  }
  return keys[keys.length - 1][1];
};

export type Shot = {t: number; zoom: number; x?: number; y?: number};

// Screen Studio-style camera: zooms the whole stage toward a point in window
// points, keeping that point at the window's centre. Shots without x/y frame
// the full window.
export const Camera: React.FC<{
  t: number; win: Rect; shots: Shot[]; children: React.ReactNode;
}> = ({t, win, shots, children}) => {
  const cx = win.x + win.w / 2;
  const cy = win.y + win.h / 2;
  const focus = shots.map((s) => (s.x === undefined ? {x: cx, y: cy} : toCanvas(win, s.x, s.y!)));
  const z = track(t, shots.map((s) => [s.t, s.zoom]));
  const fx = track(t, shots.map((s, i) => [s.t, focus[i].x]));
  const fy = track(t, shots.map((s, i) => [s.t, focus[i].y]));
  return (
    <AbsoluteFill style={{transformOrigin: '0 0',
      transform: `translate(${cx - fx * z}px, ${cy - fy * z}px) scale(${z})`}}>
      {children}
    </AbsoluteFill>
  );
};

// The recording in a window that swings in from a 3D tilt and then settles.
export const TiltWindow: React.FC<{
  clip: string; win: Rect; startFrom: number; rate: number; hold?: number;
}> = ({clip, win, startFrom, rate, hold = HOLD}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const s = spring({frame: frame - ENTER, fps, config: {damping: 18, mass: 0.9}, durationInFrames: sec(0.93)});
  const video = (
    <OffthreadVideo src={staticFile(`footage/${clip}`)} startFrom={Math.round(startFrom * fps)}
      playbackRate={rate} muted style={{width: '100%', height: '100%', objectFit: 'cover'}} />
  );
  return (
    <AbsoluteFill style={{perspective: 1800}}>
      <div style={{position: 'absolute', left: win.x, top: win.y, width: win.w, height: win.h,
        borderRadius: radius.lg, overflow: 'hidden', background: color.surface, boxShadow: shadowWindow,
        transformOrigin: '50% 100%', opacity: Math.min(1, s * 1.6),
        transform: `translateY(${(1 - s) * 160}px) rotateX(${(1 - s) * 28}deg) rotateZ(${(1 - s) * -3}deg) scale(${0.86 + s * 0.14})`}}>
        {frame < hold ? (
          <Freeze frame={0}>{video}</Freeze>
        ) : (
          <Sequence from={hold} layout="none">{video}</Sequence>
        )}
      </div>
    </AbsoluteFill>
  );
};

// A drawn pointer that glides between targets and ripples on clicks.
export const Cursor: React.FC<{
  t: number; win: Rect; path: [number, number, number][]; clicks: number[];
}> = ({t, win, path, clicks}) => {
  // Arrive at each target by its time, leaving the previous one 0.35 s before.
  const keys = (i: 0 | 1) => {
    const out: [number, number][] = [];
    path.forEach(([pt, x, y], k) => {
      const v = i === 0 ? x : y;
      if (k > 0) out.push([pt - 0.35, out[out.length - 1][1]]);
      out.push([pt, v]);
    });
    return out;
  };
  const p = toCanvas(win, track(t, keys(0)), track(t, keys(1)));
  const last = clicks.filter((c) => c <= t).pop();
  const since = last === undefined ? 99 : t - last;
  const press = since < 0.12 ? 0.85 : 1;
  const ring = interpolate(since, [0, 0.45], [0, 1], {extrapolateRight: 'clamp'});
  return (
    <>
      {since < 0.45 && (
        <div style={{position: 'absolute', left: p.x - 30, top: p.y - 30, width: 60, height: 60,
          borderRadius: '50%', border: `3px solid ${color.amber}`,
          opacity: 1 - ring, transform: `scale(${0.3 + ring})`}} />
      )}
      <svg width={34} height={34} viewBox="0 0 24 24" style={{position: 'absolute', left: p.x - 4, top: p.y - 2,
        transform: `scale(${press})`, transformOrigin: '4px 2px', filter: 'drop-shadow(0 3px 6px rgba(0,0,0,.5))'}}>
        <path d="M4 2 L4 19 L8.5 15 L11.5 21.5 L14.2 20.3 L11.3 14 L17.5 14 Z" fill="#ffffff" stroke="#111111" strokeWidth={1.2} strokeLinejoin="round" />
      </svg>
    </>
  );
};

// A spring "pop" that lives from `at` for `life` seconds of clip time.
export const usePop = (t: number, at: number, life = 1.4) => {
  const {fps} = useVideoConfig();
  const local = t - at;
  if (local < 0 || local > life) return 0;
  const inn = spring({frame: local * fps, fps, config: {damping: 11, mass: 0.6}});
  const out = interpolate(local, [life - 0.3, life], [1, 0], {extrapolateLeft: 'clamp'});
  return inn * out;
};

// A floating keycap that springs up beside the action.
export const KeyPop: React.FC<{
  f: Fonts; t: number; at: number; win: Rect; x: number; y: number; label: string;
}> = ({f, t, at, win, x, y, label}) => {
  const k = usePop(t, at, 1.1);
  if (!k) return null;
  const p = toCanvas(win, x, y);
  return (
    <div style={{position: 'absolute', left: p.x, top: p.y, transform: `translate(-50%, -50%) translateY(${(1 - k) * 20}px) scale(${k})`,
      minWidth: 56, height: 56, padding: '0 14px', borderRadius: radius.md, display: 'flex', alignItems: 'center',
      justifyContent: 'center', background: color.amber, color: color.onAmber, fontFamily: f.mono, fontWeight: 700,
      fontSize: 28, boxShadow: '0 10px 30px rgba(0,0,0,.45)'}}>{label}</div>
  );
};

// Words rise in one after another.
export const KineticTitle: React.FC<{
  f: Fonts; text: string; size: number; delay?: number; style?: React.CSSProperties;
}> = ({f, text, size, delay = 0, style}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return (
    <h1 style={{margin: 0, fontFamily: f.display, fontWeight: 800, fontSize: size, lineHeight: 1,
      letterSpacing: '-0.025em', color: color.ink, display: 'flex', flexWrap: 'wrap', gap: '0 0.25em', ...style}}>
      {text.split(' ').map((w, i) => {
        const s = spring({frame: frame - delay - i * sec(0.13), fps, config: {damping: 16, mass: 0.7}});
        return (
          <span key={i} style={{display: 'inline-block', overflow: 'hidden', paddingBottom: '0.08em'}}>
            <span style={{display: 'inline-block', transform: `translateY(${(1 - s) * 110}%)`}}>{w}</span>
          </span>
        );
      })}
    </h1>
  );
};

// Headline and caption at the top left that fade out as the camera zooms in.
export const LiveTitle: React.FC<{
  f: Fonts; title: string; caption: string; zoom: number; step?: string;
}> = ({f, title, caption, zoom, step}) => {
  const frame = useCurrentFrame();
  const fade = interpolate(zoom, [1, 1.2], [1, 0], {extrapolateRight: 'clamp'});
  const cap = interpolate(frame, [ENTER + sec(0.47), ENTER + sec(0.87)], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return (
    <div style={{position: 'absolute', left: 128, top: 72, opacity: fade}}>
      {step && (
        <div style={{fontFamily: f.sans, fontWeight: 600, fontSize: 22, letterSpacing: '0.08em',
          textTransform: 'uppercase', color: color.amber, marginBottom: 10, opacity: cap}}>{step}</div>
      )}
      <KineticTitle f={f} text={title} size={72} delay={ENTER} />
      <p style={{margin: '14px 0 0', fontFamily: f.sans, fontWeight: 500, fontSize: 30, color: color.inkMuted,
        opacity: cap}}>{caption}</p>
    </div>
  );
};

// A camera-style readout at the top right while [at, until) in clip time:
// the icon's crop-mark brackets close in like focus locking, and the text
// pulls from soft to sharp.
export const Readout: React.FC<{
  f: Fonts; time: number; at: number; until: number; title: string; label: string;
}> = ({f, time, at, until, title, label}) => {
  const {fps} = useVideoConfig();
  const local = time - at;
  if (local < 0 || local > until - at) return null;
  const lock = spring({frame: local * fps, fps, config: {damping: 14, mass: 0.5}});
  const locked = local > 0.28;
  const out = interpolate(local, [until - at - 0.3, until - at], [1, 0], {extrapolateLeft: 'clamp'});
  const gap = (1 - lock) * 22;
  const ink = locked ? color.amber : 'rgba(238, 240, 243, 0.55)';
  const arm = 20;
  const corner = (v: 'top' | 'bottom', h: 'left' | 'right') => (
    <span style={{position: 'absolute', [v]: -gap, [h]: -gap, width: arm, height: arm,
      [`border${v === 'top' ? 'Top' : 'Bottom'}`]: `3px solid ${ink}`,
      [`border${h === 'left' ? 'Left' : 'Right'}`]: `3px solid ${ink}`}} />
  );
  const sharp = interpolate(local, [0.05, 0.35], [8, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return (
    <div style={{position: 'absolute', right: 128, top: 72, opacity: out, padding: '18px 26px',
      background: 'rgba(20, 23, 28, 0.9)', whiteSpace: 'nowrap'}}>
      {corner('top', 'left')}{corner('top', 'right')}{corner('bottom', 'left')}{corner('bottom', 'right')}
      <div style={{filter: `blur(${sharp}px)`, opacity: Math.min(1, local / 0.15)}}>
        <div style={{fontFamily: f.display, fontWeight: 800, fontSize: 40, lineHeight: 1.05,
          letterSpacing: '-0.02em', color: color.ink}}>{title}</div>
        <div style={{marginTop: 8, fontFamily: f.mono, fontWeight: 500, fontSize: 18, color: color.inkMuted}}>{label}</div>
      </div>
    </div>
  );
};
