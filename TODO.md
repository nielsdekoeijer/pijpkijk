# pijpkijk improvement plan

## Bugs

- [ ] **`update_graph_metadata` resets ALL node positions on any graph change** (`pipewire.zig:650-849`): every time `nodes_dirty` is set (node/port/link added or removed), `drain()` calls `update_graph_metadata()` which recalculates x/y/z for every node. This destroys any manual arrangement the user made by dragging nodes.
- [ ] **Blending artifacts with depth test** (`util.zig:1496-1509`): the quad pipeline enables both `depthWriteEnable = VK_TRUE` and alpha blending. When translucent quads overlap (e.g. node borders behind node fills), the first-drawn quad writes depth, causing the second to be discarded by depth test instead of blending. This is the "janky blending" from the original TODO.

## Compatibility

- [ ] **No PipeWire daemon reconnection**: if PipeWire restarts, the fd becomes invalid and the event loop silently stops processing audio events. No detection or reconnection logic exists.

## Code Quality / Simplification

- [ ] **Monolithic 1200-line `run()` function** (`root.zig:537-1708`): input handling, state updates, vertex building, command recording, and presentation are all in one function. Splitting into `processInput()`, `buildVertices()`, `recordAndSubmit()` would improve readability.
- [ ] **Search results computed multiple times per frame** (`root.zig:1294-1540`): `getSearchResults()`/`getPortSearchResults()` is called separately for overlay sizing, highlight positioning, and text rendering. Cache once per frame.
- [ ] **Three near-identical pipeline creation functions** (`util.zig:1390-1868`): `initQuadVertexVkGraphicsPipeline`, `initBezierVertexVkGraphicsPipeline`, and `initTextVertexVkGraphicsPipeline` are ~95% identical. Parameterize the differences (vertex type, depth test, sample shading).
- [ ] **`gpu_frame_ready` array written but never read** (`root.zig:547,1221`): set to false after fence reset but never checked anywhere. Dead code.
- [ ] **Overlays rendered in world space**: help overlay and search dialog are placed at camera-relative world coordinates with inverse-scale transforms. A screen-space pass with identity camera would avoid scaling artifacts and simplify the math.
