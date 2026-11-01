#!/bin/sh
# Builds the page's media from the product video project:
# - app screenshots and before/after frames, cut from the screen recordings
# - the intro video (EN, VI) re-encoded for the web, plus a poster frame
#
# Needs ffmpeg, and `npm run render` / `npx remotion render RawPreviewIntroVI`
# run first in ../video (they write out/rawpreview-intro-{en,vi}.mp4).
set -e
cd "$(dirname "$0")/.."

FOOTAGE=../video/public/footage
OUT=../video/out
SCREENS=src/assets/screens
LOOKS=src/assets/looks
VIDEO=public/video

mkdir -p "$SCREENS" "$LOOKS" "$VIDEO"

frame() { # clip, second, output
  ffmpeg -loglevel error -y -ss "$2" -i "$1" -frames:v 1 "$3"
}

# Whole app window (the recordings are the window at 1600 × 1076).
frame "$FOOTAGE/01-preview.mp4" 10 "$SCREENS/preview.png"
frame "$FOOTAGE/03-cull.mp4" 11.8 "$SCREENS/cull.png"
frame "$FOOTAGE/05-airdrop.mp4" 13.2 "$SCREENS/share.png"
frame "$FOOTAGE/04-copy.mp4" 4.2 "$SCREENS/copy.png"

# The photo area of Single Image view (DSC_6773.NEF), as the app rendered each look.
photo() { # second, output
  ffmpeg -loglevel error -y -ss "$1" -i "$FOOTAGE/raw/02-looks-uncut.mp4" \
    -frames:v 1 -vf "crop=938:626:286:199" "$2"
}
photo 0.3 "$LOOKS/original.png"
photo 9 "$LOOKS/tokyo-neon-night.png"
photo 11.5 "$LOOKS/adox-silvermax-21.png"
photo 13.5 "$LOOKS/adox-color-implosion.png"

for lang in en vi; do
  ffmpeg -loglevel error -y -i "$OUT/rawpreview-intro-$lang.mp4" \
    -c:v libx264 -preset slow -crf 24 -pix_fmt yuv420p -c:a aac -b:a 128k \
    -movflags +faststart "$VIDEO/rawpreview-intro-$lang.mp4"
done
frame "$OUT/rawpreview-intro-en.mp4" 2.2 "$VIDEO/poster-en.jpg"
frame "$OUT/rawpreview-intro-vi.mp4" 2.2 "$VIDEO/poster-vi.jpg"
