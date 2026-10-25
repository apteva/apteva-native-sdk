# Changelog

## 1.5.1

- Apple: make the native chat composer one line by default, expanding with its message.
- Use native Liquid Glass with a transparent surrounding inset instead of an opaque input panel.
- Keep accessible send targets and interactive keyboard dismissal.
- Wire behavior and Android rendering remain unchanged.

## 1.5.0

- Render native Conversations alert, approval, report and interactive question cards.
- Preserve custom approval actions, notes, completed decisions and required inputs.
- Reconcile completed cards after reconnect without discarding newer live events.
- Expose matching Kotlin card semantics and Android chat surface metadata.
- Retain authenticated notification routing and private-by-default preview settings.

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
