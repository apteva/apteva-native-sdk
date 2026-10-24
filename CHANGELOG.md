# Changelog

## 1.4.0

- Add typed, authenticated notification preview preference APIs for Swift and Kotlin.
- Detect preview support without changing older-server behavior. Previews remain
  hidden until the user opts in, separately from delivery channel preferences.
- Preserve notification IDs, authenticated destinations and badge/read semantics.

## 1.2.1

- Apple: read/update the optional project-scoped mobile favourite through the
  existing revision-protected UI layout API, independently of desktop pins.
- UIKit: expose the installed-app raster/SVG decoder for native navigation icons.
- Backwards-compatible additions; wire contract and Android remain at 1.2.0.
