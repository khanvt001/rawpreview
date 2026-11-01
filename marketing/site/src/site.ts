import type {Lang} from './i18n/copy';

// Where "Download for macOS" points. Set PUBLIC_DOWNLOAD_URL at build time
// (a GitHub release asset, a CDN link to the notarized DMG…).
export const DOWNLOAD_URL: string = import.meta.env.PUBLIC_DOWNLOAD_URL || '#download';

const base = import.meta.env.BASE_URL.replace(/\/?$/, '/');

// A path inside the site, respecting the base path.
export const href = (path = '') => base + path.replace(/^\//, '');

export const homeOf = (lang: Lang) => href(lang === 'en' ? '' : `${lang}/`);
