# Brisa

Brisa is a native macOS ambient-sound app for focus, rest, and sleep. Build a soundscape, save it, then control it from the menu bar. It runs locally with no account, ads, or network requests during use.

## Download

1. Open the latest [GitHub Release](../../releases/latest).
2. Download `Brisa-macOS-arm64.dmg`.
3. Open the DMG and drag **Brisa** into **Applications**.
4. Open Brisa from Applications.

The first launch includes a short introduction. If macOS asks for input-monitoring permissions, only enable them when you want keyboard sounds outside Brisa.

> Brisa currently supports Apple Silicon Macs (M1 or newer) running macOS 13 or later.

## Features

- Ambient library: noise, water, nature, and indoor environments.
- Saved, editable mixes; favorites; timer; and individual sound levels.
- Glass-style player and a compact menu-bar player with mute, volume, timer, and quick sound switching.
- Optional global keyboard and mouse sounds using recorded samples.
- A first-run welcome flow and local, persistent preferences.

## Build from source

Install Xcode Command Line Tools first:

```sh
xcode-select --install
```

Then build and run:

```sh
cd Brisa
./Scripts/build.sh
open build/Brisa.app
```

To create the drag-to-Applications installer:

```sh
cd Brisa
./Scripts/package-dmg.sh
```

The resulting file is `Brisa/release/Brisa-macOS-arm64.dmg`.

## GitHub releases

Pushing a version tag such as `v1.0.0` runs the release workflow. It builds the app, creates the DMG, and attaches it to a GitHub Release automatically. The application is ad-hoc signed for local use. For wider distribution, replace this with a Developer ID signature and Apple notarization.

## Global keyboard sounds

Enable **Interaction sounds** inside Brisa, then authorize Brisa in **System Settings → Privacy & Security → Accessibility**. Some macOS versions also require **Input Monitoring**. Brisa only observes event type and repeat state; it does not read, store, or transmit typed text.

## Project layout

```text
Brisa/
  Assets/                      Source image and macOS app icon
  Resources/Audio/             Local audio bundled in the app
  Resources/CREDITOS-AUDIO.md  Audio sources and licenses
  Scripts/build.sh             Local app build
  Scripts/package-dmg.sh       Drag-to-Applications DMG build
  Sources.swift                SwiftUI application
```

## License

Brisa source code is released under the [MIT License](LICENSE). Audio files retain their own licenses; see [audio credits](Brisa/Resources/CREDITOS-AUDIO.md).
