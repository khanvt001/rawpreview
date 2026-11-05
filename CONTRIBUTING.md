# Contributing

Thanks for helping with RawPreview. It's maintained by one person in their spare time, so replies may take a while.

## Before you start

- **Bugs:** open an issue with your macOS version, camera model and file format.
- **Features:** open an issue first. RawPreview does one job, getting photos from a card to a phone quickly, so a feature can be good and still not fit.
- **Small fixes:** go straight to a pull request.

## Setup

Follow [Build from source](README.md#build-from-source). You don't need an Apple Developer account.

## Tests

Run them with ⌘U in Xcode, or:

```sh
xcodebuild test -project rawpreview.xcodeproj -scheme rawpreview -destination 'platform=macOS'
```

## Project layout

| Path | Contents |
| --- | --- |
| `rawpreview/App`, `Views`, `ViewModels` | SwiftUI app and state |
| `rawpreview/Services` | Scanning, copying, sharing, export, metadata |
| `rawpreview/Utilities` | Decoding, rendering, caches, Metal kernels |
| `rawpreview/Models` | Data types and preset handling |
| `rawpreviewTests` | Unit tests |
| `Config` | Build settings |
| `scripts` | DMG build, built-in preset packing |
| `marketing` | Landing page and product video |

## Pull requests

- Keep each pull request to one change, and describe what you tested.
- Run the tests, and add some for changes to parsing or color math. Tests cover the logic only, so also run the app and try your change with real files. Say which cameras or formats you tried.
- Add both English and Vietnamese for new text. Strings live in `rawpreview/Localizable.xcstrings`. If you can't write Vietnamese, leave it blank and say so in the pull request.
- Don't commit RAW files or other photos, and never commit `Config/Local.xcconfig`.
- Don't change `rawpreview/Resources/BuiltInPresets.json` by hand. `scripts/build_builtin_presets.py` generates it.

By submitting a pull request, you agree that your contribution is licensed under the [MIT License](LICENSE).
