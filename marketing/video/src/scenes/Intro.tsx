import React from 'react';
import {spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {Sfx} from '../audio';
import {Blocks, Ground, Icon, useRise} from '../components';
import {KineticTitle} from '../motion';
import {SAFE, color, sec} from '../tokens';
import type {SceneProps} from './types';

export const Intro: React.FC<SceneProps> = ({f, t}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const s = spring({frame, fps, config: {damping: 12, mass: 0.8}});
  const cap = useRise(sec(0.73));
  return (
    <Ground>
      <Sfx at={sec(0.05)} kind="pop" />
      <Blocks side="right" />
      <Icon size={240} style={{position: 'absolute', left: SAFE - 16, top: SAFE - 16,
        transform: `scale(${s}) rotate(${(1 - s) * -12}deg)`}} />
      <div style={{position: 'absolute', left: SAFE, bottom: SAFE, width: 1000}}>
        <KineticTitle f={f} text="RawPreview" size={140} delay={sec(0.27)} style={{lineHeight: 0.92, letterSpacing: '-0.03em'}} />
        <p style={{...cap, margin: '28px 0 0', fontFamily: f.sans, fontWeight: 500, fontSize: 36, lineHeight: '46px',
          color: color.inkMuted}}>{t.tagline}</p>
      </div>
    </Ground>
  );
};
