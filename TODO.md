# pijpkijk improvement plan

## Bugs

- [ ] **Double-free on `name_found` in PipeWire node registration** (`pipewire.zig:425-444`): `name_found` is the same allocation stored in both `self.nodes` and `self.pipewire_nodes`. On `deinit`, `nodes` iterator calls `node.deinit()` which frees `self.name`, then `pipewire_nodes.deinit()` calls its own `PipewireNode.deinit()` which frees the same pointer again. Crash on shutdown.
- [ ] **Wrong errdefer on vertex buffer sets** (`root.zig:458,468`): both the `bezier_vertex_buffer_set` and `text_vertex_buffer_set` errdefers reference `self.quad_vertex_buffer_set` instead of their own buffer sets. If init fails partway through, the wrong buffers are freed (leaking the real ones, double-freeing quad).
- [ ] **Vertex buffer overflow / GPU memory corruption** (`root.zig:1328-1333,1398-1403,1543-1546`): vertex buffers are allocated for 100,000 entries but `@memcpy` to mapped GPU memory never checks if `items.len` exceeds the allocation. A sufficiently large PipeWire graph (many nodes, ports, text glyphs) will write past the buffer and corrupt GPU memory or crash.
- [ ] **`typed_codepoint` truncated from u21 to u8 via @intCast** (`root.zig:1014`): `search_buf` is `[128]u8`, so `@intCast(cp)` where `cp: u21` will panic on any non-ASCII codepoint (e.g. pressing a key that produces a character above 127). Typing on a non-English keyboard layout will crash the app.
- [ ] **`sampleShadingEnable = VK_TRUE` without enabling `sampleRateShading` device feature** (`util.zig:1806` vs `util.zig:915-917`): the text pipeline enables sample shading but the device creation only requests `samplerAnisotropy`. Per Vulkan spec, this is invalid — strict drivers / validation layers will reject it, and behavior is undefined.
- [ ] **Port removal not handled in `onGlobalRemove`** (`pipewire.zig:548-581`): when PipeWire destroys a port, `onGlobalRemove` checks if the ID is a node (removes it) or a link (removes from connections), but never checks if it's a port. Stale port entries remain in their parent node's `inps`/`outs` maps, causing phantom ports to render and potentially crashing when their connections are accessed.
- [ ] **`update_graph_metadata` resets ALL node positions on any graph change** (`pipewire.zig:650-849`): every time `nodes_dirty` is set (node/port/link added or removed), `drain()` calls `update_graph_metadata()` which recalculates x/y/z for every node. This destroys any manual arrangement the user made by dragging nodes.
- [ ] **PipeWire link/port event ordering race** (`pipewire.zig:352-382`): if PipeWire sends a LINK event before the referenced PORT or NODE events arrive, the lookups `self.nodes.getPtr(out_node_id)` or `out_node.outs.getPtr(out_port_id)` fail, returning `error.PipewireError`, which propagates to the C callback's `errdefer @panic`. This is a real race with PipeWire's event delivery order.
- [ ] **`VK_API_VERSION_1_4` requested** (`util.zig:252`): most drivers (especially on older hardware, VMs, or embedded GPUs) do not support Vulkan 1.4. Instance creation will fail. The app only uses Vulkan 1.0 features — this should be `VK_API_VERSION_1_0`.
- [ ] **Blending artifacts with depth test** (`util.zig:1496-1509`): the quad pipeline enables both `depthWriteEnable = VK_TRUE` and alpha blending. When translucent quads overlap (e.g. node borders behind node fills), the first-drawn quad writes depth, causing the second to be discarded by depth test instead of blending. This is the "janky blending" from the original TODO.

## Compatibility

- [ ] **No PipeWire daemon reconnection**: if PipeWire restarts, the fd becomes invalid and the event loop silently stops processing audio events. No detection or reconnection logic exists.

## Code Quality / Simplification

- [ ] **Remove vestigial `pipewire_nodes`/`pipewire_links`/`pipewire_ports` maps** (`pipewire.zig:51-53`): these duplicate data already in `self.nodes` and are never read after insertion. They also cause the double-free bug above. Removing them fixes the bug and simplifies the code.
- [ ] **Monolithic 1200-line `run()` function** (`root.zig:537-1708`): input handling, state updates, vertex building, command recording, and presentation are all in one function. Splitting into `processInput()`, `buildVertices()`, `recordAndSubmit()` would improve readability.
- [ ] **Search results computed 3 times per frame** (`root.zig:1294-1540`): `getSearchResults()`/`getPortSearchResults()` is called separately for overlay sizing, highlight positioning, and text rendering. Cache once per frame.
- [ ] **Three near-identical pipeline creation functions** (`util.zig:1390-1868`): `initQuadVertexVkGraphicsPipeline`, `initBezierVertexVkGraphicsPipeline`, and `initTextVertexVkGraphicsPipeline` are ~95% identical. Parameterize the differences (vertex type, depth test, sample shading).
- [ ] **`gpu_frame_ready` array written but never read** (`root.zig:547,1221`): set to false after fence reset but never checked anywhere. Dead code.
- [ ] **Overlays rendered in world space**: help overlay and search dialog are placed at camera-relative world coordinates with inverse-scale transforms. A screen-space pass with identity camera would avoid scaling artifacts and simplify the math.
