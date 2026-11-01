import React from 'react';
import {Composition} from 'remotion';
import {DURATION, RawPreviewIntro} from './Video';
import {FPS} from './tokens';

export const Root: React.FC = () => (
  <>
    <Composition id="RawPreviewIntro" component={RawPreviewIntro} durationInFrames={DURATION}
      fps={FPS} width={1920} height={1080} defaultProps={{lang: 'en' as const}} />
    <Composition id="RawPreviewIntroVI" component={RawPreviewIntro} durationInFrames={DURATION}
      fps={FPS} width={1920} height={1080} defaultProps={{lang: 'vi' as const}} />
  </>
);
