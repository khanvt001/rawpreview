import type {Lang} from './i18n/copy';

// Where "Download for macOS" points. Set PUBLIC_DOWNLOAD_URL at build time
// (a GitHub release asset, a CDN link to the notarized DMG…).
export const DOWNLOAD_URL: string = import.meta.env.PUBLIC_DOWNLOAD_URL || '#download';

export const GITHUB_URL = 'https://github.com/khanvt001/rawpreview';
export const EMULSION_PRESETS_URL = 'https://github.com/peva3/EmulsionPresets';
export const PEVA3_URL = 'https://github.com/peva3';
export const ESSENTIAL_PRESETS_URL = 'https://github.com/jstanx/essential-lightroom-presets';
export const JSTANX_URL = 'https://github.com/jstanx';

const base = import.meta.env.BASE_URL.replace(/\/?$/, '/');

// A path inside the site, respecting the base path.
export const href = (path = '') => base + path.replace(/^\//, '');

export const homeOf = (lang: Lang) => href(lang === 'en' ? '' : `${lang}/`);
