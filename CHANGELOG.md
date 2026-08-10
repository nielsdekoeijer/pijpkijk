# Changelog

## v0.8.0

X11/XCB backend support and runtime backend detection.

- X11 backend via libxcb: keyboard, mouse, scroll, window management
- Runtime backend detection: auto-selects Wayland if `WAYLAND_DISPLAY` is set, falls back to X11
- `PIJPKIJK_BACKEND` env var override (`wayland` or `x11`) for testing
- Comptime-generic `App` struct — both backends compiled in, zero runtime overhead
- XCB libraries statically linked (no new shared lib deps)
- Graceful degradation on X11: no pinch-to-zoom, no fractional scaling, discrete scroll
- Wider help overlay (540px → 620px)

## v0.7.0

Port search & connect, and click-to-click connections.

- `>` search: find an output port by `nodename:portname` and connect it to a target input
- `<` search: find an input port by `nodename:portname` and connect it to a target output
- Click-to-click port connections: click a port, then click another port to connect (replaces drag-hold-drop)
- Swap `/` and `?` keybindings: `/` now centers camera (view), `?` now moves node to cursor

## v0.6.0

Fuzzy node search and bug fixes.

- `?` search: find a node by name and move it to the cursor position
- `/` search: find a node and center the camera on it (live preview, restores view on cancel)
- Fuzzy matching with arrow key navigation
- Help overlay moved from `?` to `H`
- Fix overlapping node selection picking the wrong (bottom) node

## v0.5.0

Trackpad gesture support and cleanup.

- Trackpad 2-finger scroll pans the camera (mouse wheel still zooms)
- Pinch-to-zoom via zwp_pointer_gestures_v1 protocol
- Horizontal scrolling support
- Remove spammy swap extent debug logging

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
