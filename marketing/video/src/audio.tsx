import React from 'react';
import {Audio, Sequence, interpolate, staticFile} from 'remotion';
import {FPS, sec} from './tokens';

// "Fun is Fun" by Aylex (freetouse.com): 125 BPM; the drop's first kick
// hits at 9.11 s.
const BEAT = 60 / 125;
const DROP_IN_TRACK = 9.11;
// The drop arrives as the Preview scene finishes fading in.
export const DROP_AT = sec(3.5);
const TRACK_START = DROP_IN_TRACK - DROP_AT / FPS;

// The frame of the last beat at or before `frame`.
export const beatBefore = (frame: number) => {
  const beats = Math.floor((frame - DROP_AT) / (BEAT * FPS));
  return Math.round(DROP_AT + beats * BEAT * FPS);
};

export const Music: React.FC<{total: number}> = ({total}) => (
  <Audio src={staticFile('audio/music-fun-is-fun.mp3')} trimBefore={sec(TRACK_START)}
    volume={(f) => 0.2 * interpolate(f, [total - sec(2), total], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})} />
);

const files = {click: 'audio/click.mp3', pop: 'audio/pop.mp3', whoosh: 'audio/whoosh.mp3'};
const levels = {click: 0.7, pop: 0.45, whoosh: 0.35};

// One sound effect at a frame of the enclosing sequence.
export const Sfx: React.FC<{at: number; kind: keyof typeof files; volume?: number}> = ({at, kind, volume = 1}) => (
  <Sequence from={Math.max(0, Math.round(at))} durationInFrames={sec(1)} layout="none">
    <Audio src={staticFile(files[kind])} volume={levels[kind] * volume} />
  </Sequence>
);

// Frames into a live scene for a moment in clip time.
export const clipFrame = (hold: number, start: number, rate: number) => (t: number) =>
  hold + ((t - start) / rate) * FPS;
