# Changelog

## v0.4.0

DPI scaling, selection UX, and graph layout improvements.

- Fractional DPI scaling via wp_fractional_scale_v1 protocol
- Shift-extend region selection (hold shift to add to selection)
- Graceful handling of cyclical PipeWire graph dependencies

## v0.3.0

Layout, selection, and bug fixes.

- Unconnected sink nodes (have inputs, no connections) placed in last column instead of first
- Re-layout graph automatically when links or nodes are removed
- Robust thin region selection via segment-AABB intersection
- Stronger port color burn (0.4 → 0.6)
- Match selection bezier math to rendering (multi-start N-R, adjusted hit distance)
- Enlarged help overlay (540x520) with better text spacing

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
