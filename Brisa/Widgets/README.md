# Brisa widgets

`BrisaWidgets.swift` provides two native WidgetKit experiences:

- **Brisa player:** a glass-style desktop widget in small and medium sizes, with playback status, active sounds, volume, and a play/pause action.
- **Brisa control:** a compact play/pause control for macOS Control Center and the menu bar on macOS 26 or later.

Both the app and widget use the `group.local.brisa.ambient` App Group to share the current playback snapshot and the pending play/pause command. The two entitlements files must be enabled when adding the `BrisaWidgets` WidgetKit extension target in Xcode. The extension is deliberately separate from the lightweight command-line build; it needs an Apple signing team and an embedded app-extension target to be distributed by macOS.
