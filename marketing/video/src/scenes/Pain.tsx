import React from 'react';
import {Easing, interpolate, useCurrentFrame} from 'remotion';
import {BEAT, Sfx} from '../audio';
import {Ground, useRise} from '../components';
import {ENTER, KineticTitle} from '../motion';
import {SAFE, color, sec} from '../tokens';
import type {SceneProps} from './types';

// The chore RawPreview replaces: four steps through a photo editor, struck out
// one after another, before the drop brings in the app. Counting back from the
// drop, the scene's beats fall at 0.8 s + k beats, and everything lands on one.
const beat = (k: number) => sec(0.8 + k * BEAT);
const ROWS_AT = 0;      // one row per beat
const STRIKE_AT = 4;    // all four struck out, a frame apart
const SKIP_AT = 5;

const easeOut = Easing.bezier(0.2, 0.8, 0.2, 1);

const Row: React.FC<SceneProps & {i: number; text: string}> = ({f, i, text}) => {
  const frame = useCurrentFrame();
  const rise = useRise(beat(ROWS_AT + i));
  const strike = interpolate(frame - beat(STRIKE_AT) - i * sec(0.08), [0, sec(0.3)], [0, 1], {
    easing: easeOut, extrapolateLeft: 'clamp', extrapolateRight: 'clamp',
  });
  return (
    <li style={{...rise, display: 'flex', alignItems: 'center', gap: 28}}>
      <span style={{flex: 'none', width: 52, height: 52, borderRadius: 999, border: `2px solid ${color.line}`,
        display: 'grid', placeItems: 'center', fontFamily: f.mono, fontWeight: 700, fontSize: 24,
        color: color.inkMuted}}>{i + 1}</span>
      <span style={{position: 'relative', fontFamily: f.sans, fontWeight: 500, fontSize: 40, lineHeight: '52px',
        color: strike > 0.5 ? color.inkMuted : color.ink}}>
        {text}
        <span style={{position: 'absolute', left: -6, right: -6, top: '52%', height: 4, borderRadius: 2,
          background: color.inkMuted, transformOrigin: 'left center', transform: `scaleX(${strike})`}} />
      </span>
    </li>
  );
};

export const Pain: React.FC<SceneProps> = ({f, t}) => {
  const step = useRise(ENTER);
  const skip = useRise(beat(SKIP_AT));
  return (
    <Ground>
      {t.pain.steps.map((_, i) => <Sfx key={i} at={beat(ROWS_AT + i)} kind="pop" volume={0.5} />)}
      <Sfx at={beat(STRIKE_AT)} kind="whoosh" volume={0.6} />
      <Sfx at={beat(SKIP_AT)} kind="click" />
      <div style={{position: 'absolute', left: SAFE, top: 200, width: 1920 - 2 * SAFE}}>
        <div style={{...step, fontFamily: f.sans, fontWeight: 600, fontSize: 22, letterSpacing: '0.08em',
          textTransform: 'uppercase', color: color.amber, marginBottom: 14}}>{t.pain.step}</div>
        <KineticTitle f={f} text={t.pain.title} size={72} delay={ENTER} style={{letterSpacing: '-0.02em'}} />
        <ol style={{listStyle: 'none', margin: '64px 0 0', padding: 0, display: 'flex', flexDirection: 'column', gap: 26}}>
          {t.pain.steps.map((s, i) => <Row key={i} f={f} t={t} i={i} text={s} />)}
        </ol>
        <p style={{...skip, margin: '64px 0 0', fontFamily: f.display, fontWeight: 800, fontSize: 64, lineHeight: 1,
          letterSpacing: '-0.02em', color: color.ink}}>{t.pain.skip}</p>
      </div>
    </Ground>
  );
};
