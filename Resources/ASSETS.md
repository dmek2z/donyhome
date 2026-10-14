# Asset sources

- DonyLogo.png is Dony's own logo (the `dony` wordmark on blue), created by the author. The original PNG is unmodified in the sidebar. `scripts/app-icon.swift` generates a rounded full blue tile with transparent corners for the app's ICNS, avoiding the white frame around the previous opaque square artwork. No Finder custom-icon override is required; the bundle remains strictly code-signature verifiable.
- PretendardVariable.ttf comes from the upstream https://github.com/orioncactus/pretendard (`packages/pretendard/dist/public/variable/PretendardVariable.ttf`). Bundled under SIL Open Font License; see Fonts/OFL.txt. Fonts register for the process only, with no global installation.
- UI tokens and controls are original to this project (`Theme.swift`, `DonyControls.swift`): gray canvas, white cards, blue primary action, Pretendard.

- UI icons: official `@phosphor-icons/core` 2.1.1, MIT license (`Icons/LICENSE`), https://github.com/phosphor-icons/core . Selected fill, regular auxiliary actions and bold check/caret vectors are bundled as PDF with original SVG sources. Converted using build-only svglib/reportlab; there is no Python dependency at runtime.

- DonyHome battery/clipboard/pin icons use the same official Phosphor fill family, from `assets/fill/battery-high-fill.svg`, `clipboard-text-fill.svg`, and `push-pin-fill.svg`, retrieved 2026-10-13. Original SVG + PDF conversions are retained under the existing MIT notice.
- Battery/Maccy/SMC/Fuse provenance and licenses are in `Resources/Battery`, `Resources/Clipboard`, `docs/battery-integration.md` and `docs/clipboard-integration.md`. The bundled SMC is built from the included corresponding GPL source; it is a separate executable.
