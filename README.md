# pijpkijk

A minimal PipeWire graph viewer and patchbay using SDL3.

Built with Zig, SDL3, Vulkan, and PipeWire.

## Install

### Pre-built binary (recommended)

Download the latest release from [Releases](https://github.com/nielsdekoeijer/pijpkijk/releases).

```sh
tar -xzf pijpkijk-x86_64-linux.tar.gz
./pijpkijk
```

Requires glibc 2.34+ (Ubuntu 22.04+, Debian 12+, Fedora 36+, Arch).

#### Runtime dependencies

Ubuntu / Debian:
```sh
sudo apt install libvulkan1 pipewire
```

Arch (pacman):
```sh
sudo pacman -S vulkan-icd-loader pipewire
```

Arch (paru / yay):
```sh
paru -S vulkan-icd-loader pipewire
```

A Vulkan-capable GPU driver must also be installed (e.g. `mesa-vulkan-drivers` on Ubuntu, `vulkan-radeon` or `vulkan-intel` on Arch).

### Build from source (Nix)

Requires [Nix](https://nixos.org/) with flakes enabled.

```sh
# Development build
nix develop -c zig build

# Run on NixOS
nix run
```

### Remote PipeWire host

Pass an IP address to forward the remote PipeWire socket over SSH. IP addresses
use the `root` user by default; pass `user@host` to select another user.

```sh
pijpkijk 192.168.1.52
pijpkijk user@example.net
```

SSH key authentication must already be configured. The SSH process and its
temporary Unix socket are removed when pijpkijk exits.

## Controls

### Keyboard

| Key      | Action                        |
|----------|-------------------------------|
| `?`      | Show help overlay (hold)      |
| `Q`      | Quit                          |
| `R`      | Re-layout graph               |
| `L`      | Toggle auto-layout            |
| `Delete` | Delete selected connections   |
| `Escape` | Deselect / cancel drag        |

### Mouse

| Action           | Effect          |
|------------------|-----------------|
| Left click node  | Select node     |
| Drag node        | Move node       |
| Drag port        | Create link     |
| Drag empty       | Region select   |
| Shift+drag empty | Extend selection |
| Right drag       | Pan camera      |
| Scroll           | Zoom            |

## Tech stack

- **Language:** Zig 0.16
- **Display and input:** SDL3
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

## AI disclosure

Parts of this codebase were developed with assistance from Claude (Anthropic).

## License

[MIT](LICENSE)
