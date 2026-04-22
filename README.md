# Nocturn

Free, open-source macOS audio control app with per-app volume, device routing, and EQ from the menu bar.

## Requirements

- macOS 14.0+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation

## Quick start

```bash
brew install xcodegen
xcodegen generate
open Nocturn.xcodeproj
```

## Notes

- MVP in this repository targets phases 1-6 (AudioTap-based flow).
- HAL driver + release automation are planned for a later phase.
