# Source structure

- `AppEntry.swift` owns the SwiftUI app lifecycle and scene setup.
- `AppModel.swift` owns persisted user state, mix actions, playback state, and timer state.
- `Sources.swift` is the shared domain and rendering module: the sound catalog, audio engines, permission-aware input sound service, and SwiftUI views.

`AppModel` is the only place where user actions change playback, mixes, favorites, timer state, or persisted preferences. Services expose focused work only: `AudioBank` plays ambient layers and `InputSounds` handles the optional keyboard and mouse feedback.

The build script compiles `Sources.swift` and every `Sources/*.swift` file. New application-level state belongs in `AppModel`; lifecycle code belongs in `AppEntry`; and focused services or view components can be added as separate files in `Sources/`.
