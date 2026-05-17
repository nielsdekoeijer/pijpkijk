# pijpkijk: Node Graph Viewer MVP Plan

## Phase 1: The 2D Batch Renderer (Nodes)
* **Define a Vertex Struct:** Create a Zig struct with `position` (x, y) and `color` (r, g, b, a).
* **Screen-Space Projection:** Use a Push Constant or Uniform Buffer in the vertex shader for an Orthographic Projection Matrix to use pixel coordinates instead of normalized device coordinates.
* **Vertex Buffers:** Allocate an `SDL_GPUTransferBuffer`, map it, copy the quad array (nodes), unmap it, upload to an `SDL_GPUBuffer`, and bind it before drawing.

## Phase 2: Connecting the Dots (Bezier Splines)
* **CPU Tessellation:** Calculate cubic Bezier curves in Zig by evaluating points from `t = 0.0` to `t = 1.0` in small increments.
* **Line Rendering:** Render the calculated points using `SDL_GPU_PRIMITIVETYPE_LINESTRIP`.

## Phase 3: Text Rendering
* **Font Rasterization:** Integrate a C-library like `stb_truetype.h` or `freetype` to load `.ttf` files.
* **Texture Atlas:** Generate a single large texture containing all necessary glyphs at startup.
* **Textured Quads:** Draw a quad for each letter, using UV coordinates to sample the correct glyph from the texture atlas.

## Phase 4: State & Interaction
* **Logical Representation:** Define Zig structs for the graph state (`Pin`, `Node`, `Link`) that are distinct from the rendering data.
* **Interaction:** Track mouse coordinates and states (e.g., `is_dragging_node`) in the SDL event loop to update structural positions before the render pass.

## Immediate Next Steps
* Update `pipeline_info` in `root.zig` to describe the vertex layout (e.g., `position`, `color`).
* Update the Slang vertex and fragment shaders to accept and use the vertex buffer data.
