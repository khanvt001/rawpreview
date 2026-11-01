import {defineConfig} from 'astro/config';

// SITE_URL (for canonical and hreflang links) and BASE_PATH (when served from a
// sub-folder, e.g. GitHub Pages) come from the environment at build time.
export default defineConfig({
  site: process.env.SITE_URL,
  base: process.env.BASE_PATH ?? '/',
  i18n: {
    defaultLocale: 'en',
    locales: ['en', 'vi'],
    routing: {prefixDefaultLocale: false},
  },
});
