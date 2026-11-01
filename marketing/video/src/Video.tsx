import React from 'react';
import {AbsoluteFill} from 'remotion';
import {linearTiming, TransitionSeries} from '@remotion/transitions';
import {copy} from './copy';
import {fonts, type Lang} from './fonts';
import {Music, PAIN_SECONDS, Sfx, beatBefore} from './audio';
import {dip} from './dip';
import {color, sec} from './tokens';
import {Intro} from './scenes/Intro';
import {Pain} from './scenes/Pain';
import {PREVIEW_LIVE_FRAMES, PreviewLive} from './scenes/PreviewLive';
import {LOOKS_LIVE_FRAMES, LooksLive} from './scenes/LooksLive';
import {CULL_LIVE_FRAMES, CullLive} from './scenes/CullLive';
import {SHARE_LIVE_FRAMES, ShareLive} from './scenes/ShareLive';
import {COPY_LIVE_FRAMES, CopyLive} from './scenes/CopyLive';
import {Outro} from './scenes/Outro';

// Scene lengths in frames; transitions overlap neighbours by T frames.
const scenes = [
  {C: Intro, n: sec(3.5)},
  {C: Pain, n: sec(PAIN_SECONDS)},
  {C: PreviewLive, n: PREVIEW_LIVE_FRAMES},
  {C: LooksLive, n: LOOKS_LIVE_FRAMES},
  {C: CullLive, n: CULL_LIVE_FRAMES},
  {C: ShareLive, n: SHARE_LIVE_FRAMES},
  {C: CopyLive, n: COPY_LIVE_FRAMES},
  {C: Outro, n: sec(5)},
];
const T = sec(0.8);

// Trim each middle scene so the next one finishes fading in on a beat.
// Scenes only ever get shorter, by less than one beat.
const starts: number[] = [];
const lengths: number[] = [];
scenes.reduce((start, sc, i) => {
  const n = i > 0 && i < scenes.length - 1 ? beatBefore(start + sc.n) - start : sc.n;
  starts.push(start);
  lengths.push(n);
  return start + n - T;
}, 0);
export const DURATION = starts[starts.length - 1] + lengths[lengths.length - 1];

export const RawPreviewIntro: React.FC<{lang: Lang}> = ({lang}) => {
  const f = fonts(lang);
  const t = copy[lang];
  return (
    <AbsoluteFill style={{background: color.ground}}>
      <Music total={DURATION} />
      {/* A whoosh as each scene starts to come in. */}
      {starts.slice(1).map((s) => <Sfx key={s} at={s} kind="whoosh" />)}
      <TransitionSeries>
        {scenes.flatMap(({C}, i) => [
          <TransitionSeries.Sequence key={`s${i}`} durationInFrames={lengths[i]}>
            <C f={f} t={t} />
          </TransitionSeries.Sequence>,
          i < scenes.length - 1 ? (
            <TransitionSeries.Transition key={`t${i}`} presentation={dip()}
              timing={linearTiming({durationInFrames: T})} />
          ) : null,
        ])}
      </TransitionSeries>
    </AbsoluteFill>
  );
};
