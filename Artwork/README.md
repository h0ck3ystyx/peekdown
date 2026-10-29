# Peekdown icon

The eye and down arrow adapt the original inline artwork in `docs/index.html`.
The native icon keeps its ink (#0F1726), white, and highlighter yellow (#FFD84D)
identity, with transparent margins around a rounded square sized for the macOS
icon grid. Small representations use a slightly larger pupil and arrow stroke.

All artwork and generator code are Copyright 2026 Chuck Sinnett, licensed under
the repository's [MIT license](../LICENSE). There are no third-party assets or fonts.

`./scripts/generate-icon.sh` uses AppKit and `iconutil` to regenerate:

- `Artwork/Peekdown.svg`: scalable master, generated from the canonical vector
  geometry in `scripts/generate-icon.swift`.
- `build/icon/Peekdown.iconset`: 16, 32, 128, 256, and 512 point PNGs at 1x and 2x.
- `Peekdown/Resources/Peekdown.icns`: committed native icon containing all sizes,
  including the 1024-pixel Retina representation.

Normal builds use the committed ICNS without regenerating it. Both XcodeGen and
`build.sh` copy the same file into the host app and set `CFBundleIconFile`.
The setup window displays the bundle icon, matching Finder, Dock, and About.
Packaging preserves the complete app, including the icon, in ZIP and PKG outputs.

The landing page's animated mark is promotional artwork, not an app screenshot.
The native icon ships in v1.0.3; v1.0.2 predates this icon.

Verification: inspect the small-size contact sheet and the built bundle, decode
its ICNS with `iconutil`, and check the packaged payload before release. Finder
and Dock can cache old icons for already installed copies; test the new signed
release rather than relying on a stale installed app's appearance.

Local verification on October 29, 2026 passed: small-size light/dark contact
sheet, Finder Get Info, setup window and About panel, command-line universal
build/signatures, XcodeGen + Xcode Release build, matching versions in all three
Xcode-built bundles, ten decoded ICNS representations, and icon preservation in
both ZIP and installer payloads. Packaging was tested with an ad-hoc app and an
unsigned installer; final Developer ID signing/notarization remains a release step.
The Dock's cached presentation remains a visual check on the final installed release.
