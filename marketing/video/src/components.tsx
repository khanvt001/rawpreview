import React from 'react';
import {AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {color, radius, sec} from './tokens';

const easeOut = Easing.bezier(0.2, 0.8, 0.2, 1);

// 500 ms ease-out rise of 24px, per the VideoTitleCard guideline.
export const useRise = (delay = 0) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const t = interpolate(frame - delay, [0, fps * 0.5], [0, 1], {
    easing: easeOut, extrapolateLeft: 'clamp', extrapolateRight: 'clamp',
  });
  return {opacity: t, transform: `translateY(${(1 - t) * 24}px)`};
};

export const Ground: React.FC<{children: React.ReactNode}> = ({children}) => (
  <AbsoluteFill style={{background: color.ground}}>{children}</AbsoluteFill>
);

// Sunset-ramp blocks bleeding off an edge. Decorative only.
export const Blocks: React.FC<{side: 'right' | 'left'}> = ({side}) => {
  const frame = useCurrentFrame();
  const drift = interpolate(frame, [0, sec(10)], [0, -30], {extrapolateRight: 'clamp'});
  const pos = (n: number) => (side === 'right' ? {right: n} : {left: n});
  const block = (style: React.CSSProperties) => (
    <div style={{position: 'absolute', borderRadius: radius.lg, ...style}} />
  );
  return (
    <AbsoluteFill style={{transform: `translateY(${drift}px)`}}>
      {block({...pos(-80), top: -60, width: 520, height: 640, background: color.sun})}
      {block({...pos(200), top: 360, width: 360, height: 520, background: color.coral})}
      {block({...pos(-60), bottom: -110, width: 380, height: 420, background: color.teal})}
    </AbsoluteFill>
  );
};

export const Icon: React.FC<{size: number; style?: React.CSSProperties}> = ({size, style}) => (
  <Img src={staticFile('app-icon.png')} style={{width: size, height: size, ...style}} />
);
