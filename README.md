# pijpkijk

A minimal PipeWire graph viewer and patchbay for Wayland.

Built from scratch with Zig, raw Wayland, Vulkan, and PipeWire — no toolkit, no
SDL, no intermediate libraries.

## Install

Requires [Nix](https://nixos.org/) with flakes enabled.

```sh
# Build
nix build

# Run (NixOS)
nix run

# Run (non-NixOS, after nix build)
./result/bin/pijpkijk
```

## Runtime dependencies

- Wayland compositor
- PipeWire (running)
- Vulkan-capable GPU + driver

## Controls

### Keyboard

| Key      | Action                        |
|----------|-------------------------------|
| `?`      | Show help overlay (hold)      |
| `Q`      | Quit                          |
| `R`      | Re-layout graph               |
| `Delete` | Delete selected connections   |
| `Escape` | Deselect / cancel drag        |

### Mouse

| Action           | Effect          |
|------------------|-----------------|
| Left click node  | Select node     |
| Drag node        | Move node       |
| Drag port        | Create link     |
| Drag empty       | Region select   |
| Right drag       | Pan camera      |
| Scroll           | Zoom            |

## Tech stack

- **Language:** Zig 0.16
- **Display:** Wayland (raw protocol, no libwayland wrappers)
- **Graphics:** Vulkan
- **Audio graph:** PipeWire
- **I/O:** io_uring
- **Shaders:** Slang → SPIR-V
- **Text:** MSDF atlas rendering

## Non-goals (1.0)

- Volume / device / parameter control
- Session (patchbay persistence) management
- Node creation — link editing only
- Undo/redo

## License

[MIT](LICENSE)
