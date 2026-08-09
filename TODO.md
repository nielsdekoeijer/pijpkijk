# pijpkijk — Road to 1.0

A clean-room rewrite of the PipeWire graph viewer. **Zero AI-generated code** — this
document is the plan; every line of the implementation is written by hand.

Goal: a *minimal* PipeWire graph viewer/patchbay. Everything you need, nothing more.
Raw Wayland + Vulkan (dynamic rendering) + PipeWire + io_uring, in Zig.

---

## Guiding principles

- **One-way data flow.** PipeWire events and Wayland input flow *into* the domain
  model; the model flows *out* to the renderer. Nothing flows backwards.
  ```
  PipeWire events ─┐
                   ├─► graph/model ─► ui/scene ─► gfx/renderer ─► GPU
  Wayland input ───┘        ▲                        │
                            └──── ui/interaction ────┘
  ```
- **Strict layer boundaries.** `gfx/` knows nothing about PipeWire. `graph/` knows
  nothing about Vulkan or screen coordinates. `ui/` is the *only* bridge.
- **`ui/` owns no persistent resources.** It's pure logic over a state struct + a
  renderer handle. This is good design on its own — and it's exactly what makes code
  hot-reload (below) possible *for free*. Do not let Vulkan/PipeWire handles leak into `ui/`.
- **Typed ids.** `NodeId = enum(u32)`, `PortId`, `LinkId` — never bare `usize`/`u32`.
- **All GPU memory from one suballocator.** No raw `vkAllocateMemory` outside `gfx/memory.zig`.
- **Event-driven, render-on-demand.** This app is idle most of the time. Render only
  when something changed, throttled to the compositor via Wayland frame callbacks.
  A busy render loop is a bug — it burns battery for a static graph.
- **Interaction is one state machine**, not scattered `if (mouse_down_l)` branches.

---

## Key decisions to lock down first (consumer-facing)

These determine *who can build and run it*. Decide once, write them in the README.

- [ ] **Minimum Vulkan version.** Recommend **require 1.3** (dynamic rendering in core;
      universally available on current Mesa/2026 drivers). Check at startup; if absent,
      fail with a clear message. Alternative — support 1.2 + `VK_KHR_dynamic_rendering` —
      only if a target user is stuck on an old driver. Pick one; don't straddle.
- [ ] **Minimum Zig version.** The code uses the new `std.Io` API (`std.process.Init`,
      `std.Io`) — bleeding-edge and still churning. Pin an exact Zig in the flake
      (already 0.16.0 via zig-overlay) and state it. A tool "for people to consume" that
      needs an unreleased compiler is a hard sell — track this as a real risk.
- [ ] **What CI can actually test.** GPU + Wayland + PipeWire cannot run in ordinary CI.
      CI covers: `zig fmt --check`, `zig build`, **pure-logic unit tests**, `nix flake
      check`. Rendering is verified manually (walking skeleton + `/run`). A headless
      Vulkan smoke test via **lavapipe** + `VK_EXT_headless_surface` is a *stretch*, not
      a gate. Be honest about this rather than implying CI covers rendering.
- [ ] **Layout persistence (borderline "need").** If node positions should survive a
      restart, match on **stable node identity (name/path), not PipeWire id** — ids are
      not stable across daemon restarts. Keep optional; note the identity problem.

---

## Target module tree

```
src/
  main.zig          entry: parse args, construct App, run (~20 lines)
  cli.zig           arg parsing, --help / --version / --log-level
  log.zig           logger (port from current logger.zig — it's clean)

  platform/
    loop.zig        io_uring wrapper: registers fd sources, yields typed Event stream
    watch.zig       inotify → file-change events (feeds hot-reload; see below)
    wayland/
      window.zig    display/surface/xdg toplevel lifecycle, resize
      registry.zig  global binding
      seat.zig      pointer + keyboard → normalized InputEvent (no scattered ?bools)

  gfx/              Vulkan backend — replaces ALL of the old util.zig
    context.zig     instance, physical/logical device, queues, debug messenger
    swapchain.zig   swapchain + views + resize
    memory.zig      suballocator over a few large VkDeviceMemory blocks
    frame.zig       per-frame-in-flight: cmd buffer, sync objects, mapped buffers
    pipeline.zig    pipeline + cache (serialized to XDG cache dir)
    shaders.zig     embedded SPIR-V (release) / disk-loaded (hot-reload debug)
    text.zig        MSDF atlas load + glyph metrics + text→quad layout
    renderer.zig    high-level batch API: drawQuad/drawBezier/drawText/drawRect

  graph/            pure PipeWire domain — zero rendering knowledge
    model.zig       Node/Port/Link plain data + typed ids
    pipewire.zig    connection, registry listeners, event draining → model deltas
    commands.zig    createLink / destroyLink / destroyNode / autolayout

  ui/               the bridge + interaction (owns no persistent resources)
    camera.zig      pan/zoom, worldToScreen / screenToWorld
    selection.zig   Set(NodeId) + Set(LinkId)
    interaction.zig the input state machine (single source of truth — see below)
    scene.zig       model + camera + selection → renderer batches
    layout.zig      node placement / force-directed autolayout
    hud.zig         status bar + help overlay

  gpu_types.zig     QuadVertex / BezierVertex / TextVertex — the shared gfx↔ui contract
```

---

## Interaction model (single source of truth)

All three interactive features — pan, move, **selection box**, **create link**, and
link picking — share the pointer. Model them as one state machine so precedence is
defined, not accidental:

```zig
const InteractionState = union(enum) {
    idle,
    panning,                                       // right-drag: move camera
    dragging_selection: struct { last: Vec2 },     // left-drag on a selected node
    box_select: struct { anchor_screen: Vec2, add: bool }, // left-drag on empty canvas
    linking: struct { from_port: PortId },         // left-drag from an out-port pin
};
```

**Left-press hit-test precedence (first match wins):**
1. On an **out-port pin** → `linking` (drag toward an in-port; drop to create).
2. On a **node body** → select it (Shift = extend, else replace), then `dragging_selection`
   moves the whole current selection.
3. Near a **link** (bezier, within a threshold) → select/toggle that link.
4. On **empty canvas** → `box_select`.

Right-drag anywhere → `panning`. This ordering is the contract; both the selection-box
and create-link sections below defer to it.

---

## Selection box (rubber-band marquee)

Generalizes the old single `selected_node: ?usize` into `ui/selection.zig`.

- [ ] Left-press on empty canvas → `box_select`; record `anchor_screen`. Shift extends
      the existing selection (`add = true`); otherwise clear first.
- [ ] Drag → screen-space rect from anchor to cursor. Each frame recompute provisional
      selection: nodes whose world AABB intersects the rect. Work in **screen space** so
      the marquee stays axis-aligned regardless of zoom.
- [ ] Release → commit the provisional set into `selection`.
- [ ] Then `dragging_selection` moves all selected nodes by the same world delta; Delete
      destroys their links; Escape clears the selection.
- [ ] Render: `renderer.drawRect(screen_rect, fill, border)` emits into the quad batch in
      **screen space** (bypasses the camera), drawn last. Translucent fill + 1px border.
      Reuses the existing quad pipeline — no new pipeline.

---

## Hot-reloading (rapid development)

Two independent mechanisms, both **debug-only** (`-Dhot-reload`, compiled out of release).
Zig has no hot-reload framework — this is all DIY, so budget accordingly.

### A. Shader hot-reload — do this first (high value, low risk)
- [ ] `platform/watch.zig`: watch `src/shaders/*.slang` via **inotify**, registered as
      another fd source in the io_uring loop (no polling thread).
- [ ] On change: run `slangc` → SPIR-V into a **cache path** (never `src/`),
      `vkDeviceWaitIdle`, rebuild the affected `VkShaderModule` + `VkPipeline`, swap it
      in. Keep the old pipeline alive until frames using it have retired.
- [ ] On compile error: log it, **keep the last-good pipeline** — never crash.
- [ ] Debug loads SPIR-V from disk; release keeps `@embedFile`. One flag switches source.
- [ ] Bonus: same mechanism for the MSDF atlas (re-run `msdf-atlas-gen`, reupload the
      texture) and for a live config file.

### B. Code hot-reload — optional (powerful, invasive)
The enabling discipline (a `ui/` that owns no persistent state) is already a guiding
principle above, so you pre-pay *nothing extra* by leaving the door open. Only build
the machinery if the iteration win proves worth the ABI bookkeeping.
- [ ] **Stable host** owns everything that must survive a reload: the io_uring loop, the
      Wayland window/surface, all of `gfx/`, the PipeWire connection, and one persistent
      state arena.
- [ ] **Reloadable module** = `ui/` + graph-event handling, built as a shared library
      (`zig build-lib -dynamic`). The host `dlopen`s it and calls a stable vtable —
      `update(*State, *const FrameInput)` / `render(*State, *Renderer)`. **State lives in
      the host arena**, passed by pointer; the module owns no allocations or handles.
- [ ] `platform/watch.zig` watches the `.so`; on change: `vkDeviceWaitIdle` → `dlclose`
      → recompile → `dlopen` → rebind. State pointer untouched, so graph/camera/selection
      survive.
- [ ] **State struct is a versioned ABI contract.** POD only; a layout change forces a
      full restart (detect + log, don't corrupt).
- [ ] On module-compile failure, keep running the last-good `.so`.

### Acceptance check
- [ ] Edit a `.slang` → visible change in < ~1s, no restart, graph intact.
- [ ] Edit `ui/interaction.zig` → new behavior live, camera/selection preserved.
- [ ] Deliberate syntax error in either → app keeps running on last-good, logs the error.

---

## Phase 0 — Foundation (before app code)
- [ ] Add `LICENSE` (repo is legally un-consumable without it).
- [ ] Rewrite `README.md`: screenshot/gif, install (Nix + non-Nix), controls table,
      `--help` output, the locked-down decisions above, and non-goals.
- [ ] Add `CHANGELOG.md`; tag `v1.0.0` when this list is done.
- [x] **Fix `default.nix`**: drop `sdl3` (unused); add real `buildInputs` — `wayland`,
      `wayland-protocols`, `vulkan-headers`, `vulkan-loader`, `pipewire`, `libxkbcommon`,
      `pkg-config`. Verify `nix build` in a clean sandbox.
- [x] **Portable release binary**: `nix build` produces an FHS-compatible binary with
      wayland-client, libxkbcommon, and libffi statically linked. Only vulkan and pipewire
      remain dynamic (they dlopen drivers/plugins anyway). patchelf sets interpreter and
      rpath for standard Linux distros.
- [x] **`nix run` for NixOS testing**: wrapper app invokes the glibc dynamic linker and
      sets `LD_LIBRARY_PATH` for vulkan + pipewire from the nix store.
- [x] **`.github/workflows/release.yml`**: CI release workflow triggered on `v*` tags.
      Installs Nix, runs `nix build`, packages binary into tarball, creates GitHub Release.
- [ ] Pin `slangc` + `msdf-atlas-gen` in the flake for reproducible artifacts.
- [ ] Rework `build.zig`: generated SPIR-V / atlas flow through `LazyPath` into the Zig
      cache — **never write into `src/`**.
- [x] Single version source (inject into build; kill the 0.0.0 / 0.1.0 drift).
- [ ] `.github/workflows/ci.yml` scoped to what CI can test: `zig fmt --check`,
      `zig build`, pure-logic `zig build test`, `nix flake check`.

## Phase 1 — gfx layer + walking skeleton
> Do not write 2000 lines of Vulkan blind. Get pixels on screen through the *whole*
> pipeline early, then grow it.
- [ ] **Walking skeleton first:** window → swapchain → **dynamic rendering** → one
      hardcoded quad on screen, resize-clean. This exercises context/swapchain/frame/
      pipeline/renderer end-to-end before any features exist. Everything below grows from it.
- [ ] Flesh out `context / swapchain / memory (suballocator) / frame / pipeline(+cache) /
      renderer / text`.
- [ ] **Dynamic rendering** (Vulkan 1.3 core) — no `VkRenderPass` / `VkFramebuffer`.
- [ ] One depth image **per frame-in-flight**, not per swapchain image.
- [ ] Correct binary-semaphore WSI pattern (acquire per-frame, render-finished per-image,
      fence per-frame). No timeline semaphores on the present path.
- [ ] Renderer batch API; grow-on-demand vertex buffers with a hard cap + warning
      (replace the fixed 100k arrays).
- [ ] Check every `VkResult`; map key ones (`OUT_OF_DATE`, `DEVICE_LOST`, OOM) to named
      errors. Do not swallow `vkDeviceWaitIdle` results.
- [ ] `VK_EXT_debug_utils` object naming in debug; run clean under sync validation.
- [ ] Wire shader hot-reload here (Hot-reload §A).

## Phase 2 — platform + graph layers
- [ ] `platform/loop.zig` typed io_uring event stream; `watch.zig` inotify source.
- [ ] **Correct Wayland event-loop integration.** The old code mixes `wl_display_dispatch`
      with an external poll — the classic footgun (can block / race). Use the
      `wl_display_prepare_read` → `flush` → poll(via io_uring) → `read_events` /
      `cancel_read` → `dispatch_pending` dance instead.
- [ ] `wayland/` split into window / registry / seat; normalized `InputEvent` (retire the
      scattered nullable-bool input fields).
- [ ] `graph/model.zig` typed ids, pure data; `graph/pipewire.zig` drains events into
      model deltas (no drawing). Isolate the `_Static_assert` cImport hack in its own
      translation unit with a *why* comment.
- [ ] **PipeWire proxy-lifetime discipline.** Proxies are trivially leaked / used-after-
      free on `global_remove`. Own each proxy explicitly, destroy on removal, and never
      dereference a proxy after its global is gone. Verify with a leak-checking run while
      hot-plugging devices.
- [ ] `graph/commands.zig`: createLink / destroyLink / destroyNode / autolayout.

## Phase 3 — ui layer + features
- [ ] `camera / selection / interaction / scene / layout / hud`.
- [ ] The **interaction state machine** (above) as the one input authority.
- [ ] **Selection box** (above).
- [ ] **Create links** by dragging out-port → in-port (`linking` state). The core
      viewer→editor feature.
- [ ] **Help overlay** (F1 / ?), **status HUD** (node/link count, PipeWire connection
      state, zoom), **fit-to-graph** (`f`).
- [ ] `--help` / `--version` / `--log-level` CLI.
- [ ] (Optional) code hot-reload host/module split (Hot-reload §B).

## Phase 4 — quality & graphics pass
- [ ] **Pure-logic unit tests** (the only things CI can run): atlas parsing, glyph
      lookup, bezier/vertex math, node hit-testing, **marquee ∩ AABB intersection**,
      hit-test precedence, camera world↔screen round-trip.
- [ ] Rendering / PipeWire / Wayland verified manually via the walking skeleton + `/run`.
- [ ] Run under a leak-checking GPA; zero leaks. (The old code had an `errdefer`
      double-free at `root.zig:293/303` — don't reproduce it.)
- [ ] **DPI / fractional scaling** — biggest visible quality gap for MSDF text. Needs the
      `wp_fractional_scale` protocol XML vendored + wayland-scanner'd (like xdg-shell).
- [ ] **Cursor shapes** over pins/nodes — needs the `cursor-shape` protocol XML vendored.
- [ ] Verify sRGB end-to-end (surface format vs `R8G8B8A8_UNORM` atlas vs linear clear).
- [ ] Accessible, colorblind-distinguishable palette with contrast vs the dark
      background; hover affordances before click.
- [ ] Bezier / quad-edge AA at extreme zoom.
- [ ] Graceful startup failure UI for missing Vulkan 1.3 device / Wayland compositor /
      PipeWire daemon.

---

## Carry-over lessons from the old code (don't reproduce)
- `errdefer` double-free at `root.zig:293/303` (bezier/text errdefers freed the *quad* set).
- ~~`default.nix` depended on `sdl3` while the app links wayland/vulkan/pipewire.~~ Fixed.
- Build wrote generated artifacts into `src/` (should be cache-only).
- Version drift across `.zon` / `default.nix` / `App.version`.
- Event loop used `wl_display_dispatch` under an external poll (use the prepare_read dance).
- `pipewire.zig` knew about *drawing* (conflated domain with rendering).

## Explicit 1.0 non-goals (write these in the README)
- Volume / device / parameter control.
- Session (patchbay persistence) management.
- Node *creation* — links only for 1.0.
- **Undo/redo** — deliberately skipped: link create/destroy is symmetric and declarative,
  so re-creating a deleted link *is* the undo. Adding an undo stack would be "more."

Stay a minimal graph viewer/patchbay.
