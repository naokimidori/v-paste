# V-Paste

V-Paste is a local-first clipboard history app for macOS. It lives in the menu bar, watches the system pasteboard, and gives you a fast bottom panel for finding and reusing text, links, files, and images.

## Features

- Menu bar clipboard history for macOS
- Global shortcut to open the floating history panel
- Search, keyboard navigation, favorites, and groups
- Text, URL, file, and image clipboard items
- Link title and favicon previews
- Image thumbnails and pixel-size display
- Local SQLite storage with retention controls
- Launch-at-login and monitoring controls

## Privacy Model

V-Paste is designed to be local-first. Clipboard records are stored on your Mac under the app's Application Support directory, using the app bundle identifier as the folder name.

The app stores clipboard text, file paths for copied files, cached image assets, source app names, and source app bundle identifiers. When you copy a web URL, V-Paste may request that URL and its favicon to build a local link preview.

See [PRIVACY.md](PRIVACY.md) for the full data-handling notes.

## Requirements

- macOS 14 or newer
- Xcode with the macOS SDK
- Swift toolchain included with Xcode

This repository was prepared and verified locally with Xcode 26.3 and Swift 6.2.4.

## Build And Run

```bash
./script/build_and_run.sh
```

Useful modes:

```bash
./script/build_and_run.sh run
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
./script/build_and_run.sh --verify
```

## Run Tests

```bash
xcodebuild test \
  -project V-Paste.xcodeproj \
  -scheme V-Paste \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData
```

## Package A Local Build

```bash
./script/package_release.sh
```

The packaging script creates local unsigned artifacts under `dist/`. Unsigned builds are useful for testing, but they are not Gatekeeper-ready for public distribution. See [docs/release.md](docs/release.md) for signing, notarization, and GitHub Release guidance.

## Project Structure

```text
V-Paste/                  App source
  App/                    Application lifecycle and state wiring
  Domain/                 Clipboard models and value types
  Infrastructure/         Clipboard, SQLite, file cache, and hotkey services
  Support/                Shared support utilities
  UI/                     Menu bar, panel, cards, and settings views
V-PasteTests/             XCTest coverage
script/                   Local build and packaging helpers
docs/                     Public project documentation
```

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## License

V-Paste is released under the [MIT License](LICENSE).
