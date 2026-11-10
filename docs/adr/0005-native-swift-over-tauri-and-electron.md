# Native Swift instead of Tauri or Electron

The app is written in Swift 6 with SwiftUI, with the domain logic in a Swift package. A tool whose purpose is to explain why the machine is hot must not add a web view and its helper processes to the load, and it needs direct access to `libproc`, `sysctl` and the menu bar. Tauri and Electron would have been closer to the web stack most contributors know.

## Consequences

- The app supports macOS 26 and later on Apple silicon.
- Contributors need Xcode. The package builds and tests with `swift build` and `swift test` alone.
