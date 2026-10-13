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

A Vulkan 1.1-capable GPU driver must also be installed (e.g. `mesa-vulkan-drivers` on Ubuntu, `vulkan-radeon` or `vulkan-intel` on Arch).

### Build from source (Nix)

Requires [Nix](https://nixos.org/) with flakes enabled.

```sh
# Development build
nix develop -c zig build

# Run from the development shell (local or remote)
nix develop -c zig build run
nix develop -c zig build run -- root@192.168.192.52

# Run on NixOS
nix run
```

After updating the flake lock, re-enter `nix develop` before building/running.
The pinned development environment must be compatible with the host GPU driver.

### Remote PipeWire host

Pass an IP address to forward the remote PipeWire socket over SSH. IP addresses
use the `root` user by default; pass `user@host` to select another user.

```sh
pijpkijk 192.168.1.52
pijpkijk user@example.net
```

SSH key authentication must already be configured. The SSH process and its
temporary Unix socket are removed when pijpkijk exits.

## Latency

Each port shows **`u[min:max]`** (upstream, SPA output latency) and
**`d[min:max]`** (downstream, SPA input latency), in graph-rate samples per
channel. Rows are mirrored: **name, d, u** on the left; **u, d, name** on the
right. Both directions are available on input and output ports; different
ports retain their own values.

There is no heading row. Latency columns are measured and aligned within
each node; long port names are ellipsized. Latency text and runtime captions
share a muted gray; port names and node titles keep their original coloring. Nodes
with ports on only one side do not reserve an empty half, and graph columns
use their actual node widths.

Conversion adds every reported quantum, graph-rate frame, and nanosecond
component using the node's actual driver clock from PipeWire's profiler.
For example, two quanta plus 113 frames at 192 frames/quantum is 497 samples.
Whole-sample bounds display as integers; fractional samples are preserved.
Nonzero reported quantum components are also shown in parentheses:
`d[72720:72720](378q)` or `(min:maxq)` when the quantum bounds differ.
These quanta are already included in the sample total, not added again.
`u[-]` / `d[-]` mean a direction was not reported or the clock required to
convert quanta/nanoseconds is unavailable. Reported quantum components remain
visible even without a live clock. Frame-only bounds do not need a clock.
Stopped nodes discard their clock; no rate or quantum is guessed.

These are PipeWire-reported, propagated graph-path bounds—not the extra delay
added by this port, nor measured physical/acoustic latency. The `us` value
under the node title is CPU runtime, not signal latency.
See [PipeWire's latency model](https://docs.pipewire.org/page_latency.html).

## Controls

### Keyboard

| Key      | Action                        |
|----------|-------------------------------|
| `?`      | Show help overlay (hold)      |
| `Q`      | Quit                          |
| `R`      | Re-layout graph               |
| `L`      | Toggle auto-layout            |
| `P`      | Toggle profiling colors       |
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
