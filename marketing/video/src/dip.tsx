import React from 'react';
import {AbsoluteFill, interpolate} from 'remotion';
import type {TransitionPresentation, TransitionPresentationComponentProps} from '@remotion/transitions';

type Props = Record<string, never>;

// Fade the old scene out to the ground over the first half, then the new one
// in over the second half, so two app windows never sit on top of each other.
const Dip: React.FC<TransitionPresentationComponentProps<Props>> = ({children, presentationDirection, presentationProgress}) => {
  const opacity = presentationDirection === 'exiting'
    ? interpolate(presentationProgress, [0, 0.5], [1, 0], {extrapolateRight: 'clamp'})
    : interpolate(presentationProgress, [0.5, 1], [0, 1], {extrapolateLeft: 'clamp'});
  return <AbsoluteFill style={{opacity}}>{children}</AbsoluteFill>;
};

export const dip = (): TransitionPresentation<Props> => ({component: Dip, props: {}});
