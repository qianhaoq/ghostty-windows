# Ghostty Windows Fork

<p align="right">
  <a href="./README.md"><img alt="中文" src="https://img.shields.io/badge/中文-阅读中-1f6feb"></a>
  <a href="./README.en.md"><img alt="English" src="https://img.shields.io/badge/English-Read-2ea44f"></a>
</p>

> 非官方 Ghostty Windows 分支，聚焦原生 Windows 支持与移植。

## 项目简介

本仓库基于 Ghostty 主线代码，增加了面向 Windows 的宿主与运行时层，使 Ghostty 可以进行 Windows 方向的构建与集成。

## 与原版 Ghostty 的差异

当前分支主要聚焦 Windows 移植能力：

- 新增 Windows 应用运行时与入口（`src/main_windows.zig`、`src/apprt/windows/*`、`src/apprt/windows.zig`）。
- 新增 Windows 宿主构建链路（`src/build/GhosttyWindowsHost.zig` 及相关 build 逻辑）。
- 在命令、运行时、配置、输入、PTY、渲染等模块中补充平台适配。
- 新增 Windows 依赖整理脚本（`scripts/vendor_windows_build_deps.sh`）。
- 更新多项依赖清单（`pkg/*/build.zig.zon`）和构建配置以支持移植。

## 已完成工作

- 已集成独立的 Windows 应用层（`src/apprt/windows/`）。
- 已补充 Windows 启动路径与宿主抽象。
- 已把 Windows 构建目标接入主 Zig 构建流程。
- 已完成移植所需的跨模块兼容改造。

## 当前构建方式

Windows 移植仍在持续开发中，常见本地流程如下：

```bash
bash scripts/vendor_windows_build_deps.sh
zig build -Dtarget=x86_64-windows-gnu
```

## 当前状态

- 本仓库是实验性质分支，不是 Ghostty 官方发布通道。
- 随着上游同步和 Windows 支持推进，行为与接口可能继续调整。

## 上游项目

- Upstream Ghostty: https://github.com/ghostty-org/ghostty
- Official website: https://ghostty.org

---

如果提交 Issue 或 PR，请附上系统/工具链信息与复现步骤。
