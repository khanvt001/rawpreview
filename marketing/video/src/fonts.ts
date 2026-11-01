import {loadFont as loadArchivo} from '@remotion/google-fonts/Archivo';
import {loadFont as loadInstrument} from '@remotion/google-fonts/InstrumentSans';
import {loadFont as loadMono} from '@remotion/google-fonts/JetBrainsMono';

const archivo = loadArchivo('normal', {
  weights: ['500', '800'],
  subsets: ['latin', 'latin-ext', 'vietnamese'],
});
const instrument = loadInstrument('normal', {weights: ['500', '600'], subsets: ['latin', 'latin-ext']});
const mono = loadMono('normal', {weights: ['500', '700'], subsets: ['latin', 'vietnamese']});

export type Lang = 'en' | 'vi';

// Instrument Sans has no Vietnamese glyphs, so Vietnamese captions fall back to Archivo.
export const fonts = (lang: Lang) => ({
  display: archivo.fontFamily,
  sans: lang === 'vi' ? archivo.fontFamily : instrument.fontFamily,
  mono: mono.fontFamily,
});
