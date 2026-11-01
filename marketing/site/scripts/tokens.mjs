// Turns the RawPreview design system's tokens.json into src/styles/tokens.css.
//
// src/design/tokens.json is a copy of project/tokens.json from the design system
// (https://claude.ai/artifact/4w47cc6K3LD9YZZwG2WMDg). Copy it again after the
// system changes; this script runs before every dev and build.
import {readFileSync, writeFileSync} from 'node:fs';

const root = new URL('../', import.meta.url);
const tokens = JSON.parse(readFileSync(new URL('src/design/tokens.json', root), 'utf8'));

// The first theme (Darkroom) is the page default; the rest apply with data-theme.
const [base, ...others] = tokens.color.themes.map((t) => t.id);
const themed = [...tokens.color.tokens, ...tokens.shadow.tokens];
const valueIn = (token, theme) => (typeof token.value === 'string' ? token.value : token.value[theme] ?? token.value[base]);

const block = (selector, lines) => `${selector} {\n${lines.map((l) => `  ${l}`).join('\n')}\n}\n`;

const rootLines = [
  ...themed.map((t) => `--${t.name}: ${valueIn(t, base)};`),
  ...Object.entries(tokens.type.families).map(([name, stack]) => `--font-${name}: ${stack};`),
  ...tokens.spacing.tokens.map((t) => `--${t.name}: ${t.value};`),
  ...tokens.radius.tokens.map((t) => `--${t.name}: ${t.value};`),
  `color-scheme: ${base === 'dark' ? 'dark' : 'light'};`,
];

const themeBlocks = others.map((theme) =>
  block(`:root[data-theme='${theme}']`, [
    ...themed.filter((t) => valueIn(t, theme) !== valueIn(t, base)).map((t) => `--${t.name}: ${valueIn(t, theme)};`),
    `color-scheme: ${theme === 'dark' ? 'dark' : 'light'};`,
  ]),
);

// One class per text style; video styles stay with the video.
const px = (v) => (typeof v === 'number' ? String(v) : v);
const typeBlocks = tokens.type.groups
  .filter((g) => g.name !== 'Video')
  .flatMap((g) =>
    g.styles.map((s) => {
      const family = s.family ?? g.family;
      return block(`.${s.name}`, [
        `font-family: var(--font-${family});`,
        `font-size: ${s.fontSize};`,
        `line-height: ${px(s.lineHeight)};`,
        `font-weight: ${s.fontWeight};`,
        ...(s.letterSpacing ? [`letter-spacing: ${s.letterSpacing};`] : []),
      ]);
    }),
  );

const css = [
  `/* ${tokens.name} — generated from src/design/tokens.json by scripts/tokens.mjs. Do not edit. */\n`,
  block(':root', rootLines),
  ...themeBlocks,
  ...typeBlocks,
].join('\n');

writeFileSync(new URL('src/styles/tokens.css', root), css);
console.log('tokens.css written');
