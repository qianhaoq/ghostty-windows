# Ghostty Windows Fork / Ghostty Windows 分支

> An unofficial Ghostty fork focused on native Windows support.
> 这是一个非官方 Ghostty 分支，重点是原生 Windows 支持。

## Overview / 项目简介

**EN**
This repository tracks Ghostty and adds a Windows-oriented host/runtime layer so Ghostty can be built and run with Windows-specific integration.

**中文**
本仓库基于 Ghostty 主线代码，增加了面向 Windows 的宿主与运行时层，使 Ghostty 可以进行 Windows 方向的构建与集成。

## Differences From Upstream / 和原版 Ghostty 的差异

**EN**
Compared with upstream Ghostty, this fork currently focuses on Windows porting work:

- Adds a Windows app runtime and entrypoint (`src/main_windows.zig`, `src/apprt/windows/*`, `src/apprt/windows.zig`).
- Adds Windows host build wiring (`src/build/GhosttyWindowsHost.zig`, build graph updates).
- Extends platform handling across command/runtime/config/input/pty/renderer related modules.
- Adds dependency vendoring script for Windows builds (`scripts/vendor_windows_build_deps.sh`).
- Updates several package dependency manifests (`pkg/*/build.zig.zon`) and build configs for this port.

**中文**
与原版 Ghostty 相比，这个分支当前主要做了 Windows 移植相关工作：

- 新增 Windows 应用运行时与入口（`src/main_windows.zig`、`src/apprt/windows/*`、`src/apprt/windows.zig`）。
- 新增 Windows 宿主构建链路（`src/build/GhosttyWindowsHost.zig` 以及相关 build 逻辑）。
- 在命令、运行时、配置、输入、PTY、渲染等模块中补充平台适配。
- 新增 Windows 依赖整理脚本（`scripts/vendor_windows_build_deps.sh`）。
- 更新多项依赖清单（`pkg/*/build.zig.zon`）和构建配置以支持移植。

## What Has Been Done / 已完成内容

**EN**
- Integrated a dedicated Windows app layer under `src/apprt/windows/`.
- Added Windows-specific startup path and host abstractions.
- Connected Windows build targets into the main Zig build pipeline.
- Applied cross-module compatibility changes needed by the port.

**中文**
- 已集成独立的 Windows 应用层（`src/apprt/windows/`）。
- 已补充 Windows 启动路径与宿主抽象。
- 已把 Windows 构建目标接入主 Zig 构建流程。
- 已完成移植所需的跨模块兼容改造。

## Build (Current) / 当前构建方式

**EN**
The Windows port is still under active development. A typical local flow is:

```bash
bash scripts/vendor_windows_build_deps.sh
zig build -Dtarget=x86_64-windows-gnu
```

**中文**
Windows 移植仍在持续开发中，常见本地流程如下：

```bash
bash scripts/vendor_windows_build_deps.sh
zig build -Dtarget=x86_64-windows-gnu
```

## Status / 当前状态

**EN**
- This is an experimental fork and not an official upstream release channel.
- Behavior and APIs may change as upstream sync and Windows support evolve.

**中文**
- 本仓库是实验性质分支，不是 Ghostty 官方发布通道。
- 随着上游同步和 Windows 支持推进，行为与接口可能继续调整。

## Upstream / 上游项目

- Upstream Ghostty: https://github.com/ghostty-org/ghostty
- Official website: https://ghostty.org

---

If you open issues or PRs, please include your OS/toolchain details and reproduction steps.
如果提交 Issue 或 PR，请附上系统/工具链信息与复现步骤。
