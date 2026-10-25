# Vendored RoyalVNCKit

Upstream: github.com/royalapplications/royalvnc, tag `1.1.0` (commit `92d4427c73817d8f849bb289ff190aa4b40c44ea`).
The repo is archived, and SwiftPM can't pin it by version (it has a branch dependency and unsafeFlags), so it lives here.
Only `Sources/{RoyalVNCKit,RoyalVNCKitC,Z,d3des}` and `LICENSE` were copied. Every source patch is marked `LOCAL PATCH`.

1. `Package.swift`: iOS only, static library. Dropped swift-jpeg/swift-png (needed only on Linux, Windows and Android),
   the demo executables, `-enable-library-evolution`, `type: .dynamic` and vendored zlib (used only on Windows).
   CryptoSwift is pinned by revision (`a59b4d91`, the 1.1.0 Package.resolved SHA).
2. `Extensions/Queue.swift`: the struct had no lock, so it was racing between input callers and the send Task.
   It is now a class guarded by `NSLock`.
3. `Framebuffer/VNCFramebuffer.swift`: `ioSurface` is now `public`, so the client can make a zero-copy Metal texture.
4. Clipboard: `VNCConnectionClipboardDelegate` (new file) + `VNCConnection.clipboardDelegate` receive ServerCutText,
   and `sendClipboardText(_:)` sends ClientCutText. The app keeps `isClipboardRedirectionEnabled` off, so the
   library's own pasteboard polling (which triggers iOS paste prompts) never runs.
5. `SDK/Connection/VNCConnection+API.swift` `mouseWheel`: upstream sends only the wheel-button press for each
   step, never the release, so the server saw one long press and dropped most steps. Each step now sends press + release.
