// Darkroom theme values from the RawPreview design system (tokens.json).
// The video is always dark, so only the dark values live here.
export const color = {
  ground: '#14171c',
  surface: '#1d2128',
  surfaceRaised: '#272c35',
  slate: '#3e4551',
  line: '#353c47',
  ink: '#eef0f3',
  inkMuted: '#99a2ae',
  amber: '#f4a447',
  onAmber: '#1b1206',
  sun: '#fe9f81',
  coral: '#e6686c',
  rose: '#dd699e',
  teal: '#5a958f',
  tealInk: '#7cbab3',
  check: '#5ace7d',
};

export const radius = {xs: 4, sm: 6, md: 10, lg: 16};

// Text stays inside this margin at 1920×1080 (2 × space-16).
export const SAFE = 128;

export const shadowWindow =
  '0 32px 80px rgba(0, 0, 0, 0.55), 0 0 0 1px rgba(255, 255, 255, 0.06)';

export const FPS = 60;

// Seconds to frames at the composition's frame rate.
export const sec = (s: number) => Math.round(s * FPS);

