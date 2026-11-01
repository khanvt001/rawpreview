# Footage

Five screen recordings of RawPreview with the NIKON Z 50 card, window 1280 × 860 pt, cursor hidden, recorded at 1600 × 1076. Each file is cut to its scene's length; the uncut takes live in `raw/` (not committed).

| File | Length | What happens |
| --- | --- | --- |
| `01-preview.mp4` | 17 s | "No Source Selected", the card mounts at 1.5 s, the grid fills by 3.5 s, arrow keys scroll from 12.5 s. |
| `02-looks.mp4` | 11.7 s | DSC_6773 in Single Image with Presets open: hover previews, then Tokyo Neon Night, Adox Silvermax 21, Adox Color Implosion at 100 %. Cut from `raw/02-looks-uncut.mp4` to drop four stretches where the app fell back from a hover preview to the original photo. |
| `03-cull.mp4` | 12.1 s | Grid: 5 + S on DSC_6775, 4 on DSC_6773, 5 + S on DSC_6766, 4 + S on DSC_6762. |
| `05-airdrop.mp4` | 13.6 s | Marked grid → Copy menu → With "Tokyo Neon Night" → AirDrop as 3 JPEGs → Iphone 14, Waiting, Sending, Sent. |
| `04-copy.mp4` | 10 s | ⌘↩ copies the 3 marked files ("Copy Complete"), cut, then Done and Eject. |

Each live scene (`src/scenes/*Live.tsx`) times its camera moves, pointer, key pops and callouts to these recordings in clip seconds and window points. Re-recording a clip means re-timing its scene.
