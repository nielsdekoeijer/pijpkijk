# Changelog

## v0.2.0

Visual polish and bezier rendering fixes.

- Node border using dimmed port color
- Softer port color decay (bottom ports stay at 60% brightness)
- Thicker link curves (4px → 5px)
- More visible selection rectangle (alpha 0.25 → 0.35)
- Selected link highlight brightens toward white instead of color inversion
- Help overlay with better contrast
- Larger port-colored node titles (16px → 20px), dimmed port labels
- Text color parameter for TextVertex
- Fix bezier curves hidden behind node bodies (disable depth test on bezier pipeline)
- Fix bezier tearing on strong/180° curves (multi-start Newton-Raphson solver)
- Minimum bezier control point offset to prevent degenerate curves
- Increased bezier bounding box padding

## v0.1.0

Initial release.

- PipeWire graph viewer and patchbay
- Node dragging, region selection, camera pan/zoom
- Link creation via port dragging, link deletion
- MSDF text rendering
- Help overlay
- Portable binary via `nix build`
