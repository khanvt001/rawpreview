# RawPreview landing page

A static Astro site in English (`/`) and Vietnamese (`/vi/`), dressed in the RawPreview design system (https://claude.ai/artifact/4w47cc6K3LD9YZZwG2WMDg).

```sh
npm install
npm run dev      # http://localhost:4321
npm run build    # static files in dist/
```

## Where things come from

| What | Source |
| --- | --- |
| Colours, type, spacing, radii | `src/design/tokens.json`, a copy of the design system's `project/tokens.json`. `scripts/tokens.mjs` turns it into `src/styles/tokens.css` before every dev and build. Copy it again after the system changes. |
| Every line of text | `src/i18n/copy.ts`, both languages side by side |
| Screenshots, before/after frames, web video, posters | `npm run media` cuts them from `../video` (needs ffmpeg and the rendered videos in `../video/out`) |

## Build settings

| Variable | Purpose |
| --- | --- |
| `PUBLIC_DOWNLOAD_URL` | Where "Download for macOS" points (the notarized DMG). Without it the buttons jump to the download section. |
| `SITE_URL` | The public origin, e.g. `https://rawpreview.app`. Turns on canonical, hreflang and absolute Open Graph URLs. |
| `BASE_PATH` | Set when served from a sub-folder, e.g. `/rawpreview/` on GitHub Pages. |
