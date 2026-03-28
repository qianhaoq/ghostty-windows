# Ghostty Windows Fork

<p align="right">
  <a href="./README.md"><img alt="中文" src="https://img.shields.io/badge/中文-阅读-1f6feb"></a>
  <a href="./README.en.md"><img alt="English" src="https://img.shields.io/badge/English-Reading-2ea44f"></a>
</p>

> Unofficial Ghostty fork focused on native Windows support and porting.

## Overview

This repository tracks Ghostty and adds a Windows-oriented host/runtime layer so Ghostty can be built and run with Windows-specific integration.

## Differences From Upstream Ghostty

This fork currently focuses on Windows porting work:

- Adds a Windows app runtime and entrypoint (`src/main_windows.zig`, `src/apprt/windows/*`, `src/apprt/windows.zig`).
- Adds Windows host build wiring (`src/build/GhosttyWindowsHost.zig` and related build graph updates).
- Extends platform handling across command/runtime/config/input/pty/renderer related modules.
- Adds dependency vendoring script for Windows builds (`scripts/vendor_windows_build_deps.sh`).
- Updates several package dependency manifests (`pkg/*/build.zig.zon`) and build configs for this port.

## What Has Been Done

- Integrated a dedicated Windows app layer under `src/apprt/windows/`.
- Added Windows-specific startup path and host abstractions.
- Connected Windows build targets into the main Zig build pipeline.
- Applied cross-module compatibility changes needed by the port.

## Build (Current)

The Windows port is still under active development. A typical local flow is:

```bash
bash scripts/vendor_windows_build_deps.sh
zig build -Dtarget=x86_64-windows-gnu
```

## Status

- This is an experimental fork and not an official upstream release channel.
- Behavior and APIs may change as upstream sync and Windows support evolve.

## Upstream

- Upstream Ghostty: https://github.com/ghostty-org/ghostty
- Official website: https://ghostty.org

---

If you open issues or PRs, please include your OS/toolchain details and reproduction steps.
