import React from 'react';
import {spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {Sfx} from '../audio';
import {Blocks, Ground, Icon, useRise} from '../components';
import {ENTER, KineticTitle} from '../motion';
import {SAFE, color, radius, sec} from '../tokens';
import type {SceneProps} from './types';

export const Outro: React.FC<SceneProps> = ({f, t}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const s = spring({frame: frame - ENTER, fps, config: {damping: 200}});
  const btn = spring({frame: frame - ENTER - sec(0.8), fps, config: {damping: 10, mass: 0.6}});
  const cap = useRise(ENTER + sec(0.53));
  return (
    <Ground>
      <Sfx at={ENTER + sec(0.8)} kind="pop" />
      <Blocks side="right" />
      <Icon size={240} style={{position: 'absolute', left: SAFE - 16, top: SAFE - 16, opacity: s}} />
      <div style={{position: 'absolute', left: SAFE, bottom: SAFE + 64, width: 1000}}>
        <KineticTitle f={f} text={t.outro.title} size={140} delay={ENTER} style={{lineHeight: 0.92, letterSpacing: '-0.03em'}} />
        <div style={{display: 'flex', alignItems: 'center', gap: 32, marginTop: 36}}>
          <span style={{display: 'inline-flex', alignItems: 'center', gap: 14, padding: '20px 34px',
            borderRadius: radius.md, background: color.amber, color: color.onAmber, fontFamily: f.sans,
            fontWeight: 600, fontSize: 34, transform: `scale(${btn})`, transformOrigin: 'left center'}}>
            <svg width={32} height={32} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2}
              strokeLinecap="round" strokeLinejoin="round"><path d="M12 3v12" /><path d="m7 10 5 5 5-5" /><path d="M5 21h14" /></svg>
            {t.outro.cta}
          </span>
          <span style={{...cap, fontFamily: f.sans, fontWeight: 500, fontSize: 30, color: color.inkMuted}}>{t.outro.caption}</span>
        </div>
      </div>
      <p style={{...cap, position: 'absolute', left: SAFE, bottom: SAFE, margin: 0, fontFamily: f.sans, fontWeight: 500,
        fontSize: 22, color: color.inkMuted}}>{t.outro.credits}</p>
    </Ground>
  );
};
