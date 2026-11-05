import React from 'react';
import {Audio, Sequence, getStaticFiles, staticFile} from 'remotion';
import {FPS, sec} from './tokens';

// The cuts sit on a 125 BPM grid, so a music bed at that tempo can be added.
export const BEAT = 60 / 125;
// The grid starts as the Preview scene finishes fading in: after the 3.5 s
// intro and the usual-way scene, less the 0.8 s cut between them.
export const PAIN_SECONDS = 0.8 + 11 * BEAT;   // so the cut into it lands on a beat too
const GRID_START = sec(3.5 + PAIN_SECONDS - 0.8);

// The frame of the last beat at or before `frame`.
export const beatBefore = (frame: number) => {
  const beats = Math.floor((frame - GRID_START) / (BEAT * FPS));
  return Math.round(GRID_START + beats * BEAT * FPS);
};

const files = {click: 'audio/click.mp3', pop: 'audio/pop.mp3', whoosh: 'audio/whoosh.mp3'};
const levels = {click: 0.7, pop: 0.45, whoosh: 0.35};

// One sound effect at a frame of the enclosing sequence. The files aren't in
// the repo (see public/audio/README.md): without them the video renders silent.
export const Sfx: React.FC<{at: number; kind: keyof typeof files; volume?: number}> = ({at, kind, volume = 1}) => {
  if (!getStaticFiles().some((file) => file.name === files[kind])) return null;
  return (
    <Sequence from={Math.max(0, Math.round(at))} durationInFrames={sec(1)} layout="none">
      <Audio src={staticFile(files[kind])} volume={levels[kind] * volume} />
    </Sequence>
  );
};

// Frames into a live scene for a moment in clip time.
export const clipFrame = (hold: number, start: number, rate: number) => (t: number) =>
  hold + ((t - start) / rate) * FPS;
