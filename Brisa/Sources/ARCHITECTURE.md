# Source structure

- `AppEntry.swift` owns the SwiftUI app lifecycle and scene setup.
- `AppModel.swift` owns persisted user state, mix actions, playback state, and timer state.
- `SoundLibrary.swift` defines the available sounds and saved-mix value type.
- `AudioBank.swift` generates and plays ambient audio layers.
- `InputSounds.swift` manages optional keyboard and mouse feedback, including permissions.
- `ContentView.swift`, `WelcomeView.swift`, `InputSoundsView.swift`, `MixEditor.swift`, and `MenuBarPlayerView.swift` each own one SwiftUI surface.

`AppModel` is the only place where user actions change playback, mixes, favorites, timer state, or persisted preferences. Services expose focused work only: `AudioBank` plays ambient layers and `InputSounds` handles the optional keyboard and mouse feedback.

The build script compiles every `Sources/*.swift` file. New application-level state belongs in `AppModel`; lifecycle code belongs in `AppEntry`; and focused services or view components can be added as separate files in `Sources/`.
