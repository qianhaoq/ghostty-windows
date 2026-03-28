const std = @import("std");
const host_state = @import("apprt/windows/host_state.zig");
const win32 = @import("apprt/windows/win32.zig");
const c = @cImport({
    @cInclude("ghostty.h");
});

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.windows_host);

const class_name = std.unicode.utf8ToUtf16LeStringLiteral("GhosttyWindowHost");
const default_title = std.unicode.utf8ToUtf16LeStringLiteral("Ghostty");
const clipboard_prompt = std.unicode.utf8ToUtf16LeStringLiteral("Allow terminal access to the clipboard contents?");
const prompt_title = std.unicode.utf8ToUtf16LeStringLiteral("Ghostty");
const prompt_surface_title_message = "Enter a custom title for this terminal. Leave empty to clear the custom title.";
const prompt_tab_title_message = "Enter a custom title for this tab. Leave empty to clear the custom title.";
const prompt_search_message = "Enter search text. Leave empty to clear the active search.";

const default_client_width: u32 = 1024;
const default_client_height: u32 = 768;
const window_style = host_state.windowStyle();
const borderless_window_style = host_state.borderlessWindowStyle();
const window_ex_style = win32.WS_EX_APPWINDOW;
const WM_APP_CLOSE = win32.WM_APP + 2;

var class_registered = false;

pub fn main() !void {
    const argv = std.os.argv;
    if (c.ghostty_init(argv.len, @ptrCast(argv.ptr)) != c.GHOSTTY_SUCCESS) {
        return error.GhosttyInitFailed;
    }

    c.ghostty_cli_try_action();

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa_state.deinit();

    var host: HostApp = .{
        .alloc = gpa_state.allocator(),
        .hinstance = win32.GetModuleHandleW(null) orelse
            return error.GetModuleHandleFailed,
    };
    try host.init();
    defer host.deinit();

    _ = try host.createWindow(null);
    try host.run();
}

const HostApp = struct {
    alloc: Allocator,
    hinstance: win32.HINSTANCE,
    app: c.ghostty_app_t = null,
    windows: std.ArrayListUnmanaged(*Window) = .{},

    fn init(self: *HostApp) !void {
        try registerWindowClass(self.hinstance);

        const config = try loadConfig();
        defer c.ghostty_config_free(config);

        var runtime = std.mem.zeroInit(c.ghostty_runtime_config_s, .{});
        runtime.userdata = @ptrCast(self);
        runtime.supports_selection_clipboard = false;
        runtime.wakeup_cb = runtimeWakeup;
        runtime.action_cb = runtimeAction;
        runtime.read_clipboard_cb = runtimeReadClipboard;
        runtime.confirm_read_clipboard_cb = runtimeConfirmReadClipboard;
        runtime.write_clipboard_cb = runtimeWriteClipboard;
        runtime.close_surface_cb = runtimeCloseSurface;

        self.app = c.ghostty_app_new(&runtime, config) orelse
            return error.GhosttyAppInitFailed;
    }

    fn deinit(self: *HostApp) void {
        if (self.app != null) c.ghostty_app_free(self.app);
        self.windows.deinit(self.alloc);
    }

    fn run(_: *HostApp) !void {
        var msg: win32.MSG = undefined;
        while (true) {
            const result = win32.GetMessageW(&msg, null, 0, 0);
            if (@as(i32, result) == -1) return error.GetMessageFailed;
            if (result == 0) break;

            _ = win32.TranslateMessage(&msg);
            _ = win32.DispatchMessageW(&msg);
        }
    }

    fn createWindow(
        self: *HostApp,
        inherited: ?c.ghostty_surface_config_s,
    ) !*Window {
        const window = try self.alloc.create(Window);
        errdefer self.alloc.destroy(window);

        try window.init(self, inherited);
        errdefer window.destroyUntracked();

        try self.windows.append(self.alloc, window);
        return window;
    }

    fn removeWindow(self: *HostApp, needle: *Window) void {
        var i: usize = 0;
        while (i < self.windows.items.len) : (i += 1) {
            if (self.windows.items[i] != needle) continue;
            _ = self.windows.swapRemove(i);
            return;
        }
    }

    fn closeAll(self: *HostApp) void {
        const len = self.windows.items.len;
        for (0..len) |i| {
            _ = win32.PostMessageW(self.windows.items[i].hwnd, win32.WM_CLOSE, 0, 0);
        }

        if (len == 0) win32.PostQuitMessage(0);
    }

    fn handleAction(
        self: *HostApp,
        target: c.ghostty_target_s,
        action: c.ghostty_action_s,
    ) bool {
        switch (action.tag) {
            c.GHOSTTY_ACTION_NEW_WINDOW => {
                return self.newWindowFromTarget(target, c.GHOSTTY_SURFACE_CONTEXT_WINDOW);
            },

            c.GHOSTTY_ACTION_NEW_TAB => {
                return self.newWindowFromTarget(target, c.GHOSTTY_SURFACE_CONTEXT_TAB);
            },

            c.GHOSTTY_ACTION_NEW_SPLIT => {
                return self.newWindowFromTarget(target, c.GHOSTTY_SURFACE_CONTEXT_SPLIT);
            },

            c.GHOSTTY_ACTION_CLOSE_WINDOW => {
                const window = targetWindow(target) orelse return false;
                _ = win32.PostMessageW(window.hwnd, win32.WM_CLOSE, 0, 0);
                return true;
            },

            c.GHOSTTY_ACTION_TOGGLE_MAXIMIZE => {
                const window = targetWindow(target) orelse return false;
                window.toggleMaximize();
                return true;
            },

            c.GHOSTTY_ACTION_TOGGLE_FULLSCREEN => {
                const window = targetWindow(target) orelse return false;
                window.toggleFullscreen(action.action.toggle_fullscreen);
                return true;
            },

            c.GHOSTTY_ACTION_TOGGLE_WINDOW_DECORATIONS => {
                const window = targetWindow(target) orelse return false;
                window.toggleWindowDecorations();
                return true;
            },

            c.GHOSTTY_ACTION_TOGGLE_VISIBILITY => {
                self.toggleVisibility();
                return true;
            },

            c.GHOSTTY_ACTION_PRESENT_TERMINAL => {
                const window = targetWindow(target) orelse return false;
                window.present();
                return true;
            },

            c.GHOSTTY_ACTION_RENDER => {
                if (target.tag == c.GHOSTTY_TARGET_SURFACE) {
                    const window = windowFromSurface(target.target.surface) orelse return false;
                    _ = win32.InvalidateRect(window.hwnd, null, 0);
                    return true;
                }

                for (self.windows.items) |window| {
                    _ = win32.InvalidateRect(window.hwnd, null, 0);
                }
                return true;
            },

            c.GHOSTTY_ACTION_SET_TITLE => {
                const window = targetWindow(target) orelse return false;
                window.setTerminalTitle(std.mem.span(action.action.set_title.title));
                return true;
            },

            c.GHOSTTY_ACTION_SET_TAB_TITLE => {
                const window = targetWindow(target) orelse return false;
                window.setTabTitleOverride(std.mem.span(action.action.set_tab_title.title));
                return true;
            },

            c.GHOSTTY_ACTION_PROMPT_TITLE => {
                const window = targetWindow(target) orelse return false;
                return window.promptTitle(action.action.prompt_title);
            },

            c.GHOSTTY_ACTION_PWD => {
                const window = targetWindow(target) orelse return false;
                window.setPwd(std.mem.span(action.action.pwd.pwd));
                return true;
            },

            c.GHOSTTY_ACTION_DESKTOP_NOTIFICATION => {
                self.desktopNotification(
                    targetWindow(target),
                    std.mem.span(action.action.desktop_notification.title),
                    std.mem.span(action.action.desktop_notification.body),
                );
                return true;
            },

            c.GHOSTTY_ACTION_SHOW_CHILD_EXITED => {
                const window = targetWindow(target);
                self.showChildExited(window, action.action.child_exited);
                return true;
            },

            c.GHOSTTY_ACTION_PROGRESS_REPORT => {
                const window = targetWindow(target) orelse return false;
                window.setProgress(action.action.progress_report);
                return true;
            },

            c.GHOSTTY_ACTION_COMMAND_FINISHED => {
                const window = targetWindow(target) orelse return false;
                self.commandFinished(window, action.action.command_finished);
                return true;
            },

            c.GHOSTTY_ACTION_START_SEARCH => {
                const window = targetWindow(target) orelse return false;
                return window.startSearch(std.mem.span(action.action.start_search.needle));
            },

            c.GHOSTTY_ACTION_END_SEARCH => {
                const window = targetWindow(target) orelse return false;
                window.endSearch();
                return true;
            },

            c.GHOSTTY_ACTION_SEARCH_TOTAL => {
                const window = targetWindow(target) orelse return false;
                const total = action.action.search_total.total;
                window.search_total = if (total >= 0) @intCast(total) else null;
                window.refreshWindowTitle();
                return true;
            },

            c.GHOSTTY_ACTION_SEARCH_SELECTED => {
                const window = targetWindow(target) orelse return false;
                const selected = action.action.search_selected.selected;
                window.search_selected = if (selected >= 0) @intCast(selected) else null;
                window.refreshWindowTitle();
                return true;
            },

            c.GHOSTTY_ACTION_READONLY => {
                const window = targetWindow(target) orelse return false;
                window.readonly = action.action.readonly == c.GHOSTTY_READONLY_ON;
                window.refreshWindowTitle();
                return true;
            },

            c.GHOSTTY_ACTION_COPY_TITLE_TO_CLIPBOARD => {
                const window = targetWindow(target) orelse return false;
                return window.copyTitleToClipboard();
            },

            c.GHOSTTY_ACTION_SHOW_ON_SCREEN_KEYBOARD => {
                self.spawnDetached(&.{"osk.exe"});
                return true;
            },

            c.GHOSTTY_ACTION_MOUSE_SHAPE => {
                const window = targetWindow(target) orelse return false;
                window.cursor_id = cursorId(action.action.mouse_shape);
                window.applyCursor();
                return true;
            },

            c.GHOSTTY_ACTION_MOUSE_VISIBILITY => {
                const window = targetWindow(target) orelse return false;
                window.cursor_visible = action.action.mouse_visibility == c.GHOSTTY_MOUSE_VISIBLE;
                window.applyCursor();
                return true;
            },

            c.GHOSTTY_ACTION_INITIAL_SIZE => {
                const window = targetWindow(target) orelse return false;
                if (action.action.initial_size.width > 0 and action.action.initial_size.height > 0) {
                    window.default_width = action.action.initial_size.width;
                    window.default_height = action.action.initial_size.height;
                }
                window.setClientSize(
                    action.action.initial_size.width,
                    action.action.initial_size.height,
                );
                return true;
            },

            c.GHOSTTY_ACTION_SIZE_LIMIT => {
                const window = targetWindow(target) orelse return false;
                window.size_limit = .{
                    .min_width = action.action.size_limit.min_width,
                    .min_height = action.action.size_limit.min_height,
                    .max_width = action.action.size_limit.max_width,
                    .max_height = action.action.size_limit.max_height,
                };
                return true;
            },

            c.GHOSTTY_ACTION_RESET_WINDOW_SIZE => {
                const window = targetWindow(target) orelse return false;
                window.resetSize();
                return true;
            },

            c.GHOSTTY_ACTION_OPEN_URL => {
                self.spawnDetached(&.{
                    "rundll32",
                    "url.dll,FileProtocolHandler",
                    action.action.open_url.url[0..action.action.open_url.len],
                });
                return true;
            },

            c.GHOSTTY_ACTION_OPEN_CONFIG => {
                self.openConfig();
                return true;
            },

            c.GHOSTTY_ACTION_FLOAT_WINDOW => {
                const window = targetWindow(target) orelse return false;
                window.setFloating(action.action.float_window);
                return true;
            },

            c.GHOSTTY_ACTION_RELOAD_CONFIG => {
                self.reloadConfig(targetWindow(target));
                return true;
            },

            c.GHOSTTY_ACTION_QUIT,
            c.GHOSTTY_ACTION_CLOSE_ALL_WINDOWS,
            => {
                self.closeAll();
                return true;
            },

            c.GHOSTTY_ACTION_QUIT_TIMER => {
                if (action.action.quit_timer == c.GHOSTTY_QUIT_TIMER_START and self.windows.items.len == 0) {
                    win32.PostQuitMessage(0);
                }
                return true;
            },

            c.GHOSTTY_ACTION_RING_BELL => {
                _ = win32.MessageBeep(0);
                return true;
            },

            else => return false,
        }
    }

    fn newWindowFromTarget(
        self: *HostApp,
        target: c.ghostty_target_s,
        context: c.ghostty_surface_context_e,
    ) bool {
        var config = if (target.tag == c.GHOSTTY_TARGET_SURFACE)
            c.ghostty_surface_inherited_config(target.target.surface, context)
        else
            c.ghostty_surface_config_new();

        if (target.tag != c.GHOSTTY_TARGET_SURFACE) {
            config.context = c.GHOSTTY_SURFACE_CONTEXT_WINDOW;
        }

        _ = self.createWindow(config) catch |err| {
            log.warn("failed to create window err={}", .{err});
            return false;
        };
        return true;
    }

    fn openConfig(self: *HostApp) void {
        const path = c.ghostty_config_open_path();
        defer c.ghostty_string_free(path);

        const ptr = path.ptr orelse return;
        self.spawnDetached(&.{ "notepad.exe", ptr[0..path.len] });
    }

    fn reloadConfig(self: *HostApp, window: ?*Window) void {
        const config = loadConfig() catch |err| {
            log.warn("failed to reload config err={}", .{err});
            return;
        };
        defer c.ghostty_config_free(config);

        if (window) |v| {
            if (v.surface != null) c.ghostty_surface_update_config(v.surface, config);
            return;
        }

        c.ghostty_app_update_config(self.app, config);
    }

    fn spawnDetached(self: *HostApp, argv: []const []const u8) void {
        var child = std.process.Child.init(argv, self.alloc);
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        child.spawn() catch |err| {
            log.warn("failed to spawn child argv0={s} err={}", .{ argv[0], err });
        };
    }

    fn toggleVisibility(self: *HostApp) void {
        var any_visible = false;
        for (self.windows.items) |window| {
            if (!window.hidden) {
                any_visible = true;
                break;
            }
        }

        for (self.windows.items) |window| {
            if (any_visible) {
                window.hide();
            } else {
                window.show();
            }
        }

        if (!any_visible and self.windows.items.len > 0) {
            self.windows.items[0].present();
        }
    }

    fn desktopNotification(
        self: *HostApp,
        window: ?*Window,
        raw_title: []const u8,
        raw_body: []const u8,
    ) void {
        const title = if (raw_title.len > 0) raw_title else "Ghostty";
        const body = if (raw_body.len > 0) raw_body else title;

        if (window) |v| v.flash();

        const script = powershellBalloonScript(self.alloc, title, body) catch |err| {
            log.warn("failed to build notification script err={}", .{err});
            return;
        };
        defer self.alloc.free(script);

        if (!self.runPowerShellDetached(script)) {
            _ = win32.MessageBeep(0);
        }
    }

    fn showChildExited(
        self: *HostApp,
        window: ?*Window,
        value: c.ghostty_surface_message_childexited_s,
    ) void {
        const title = if (value.exit_code == 0)
            "Terminal Exited"
        else
            "Terminal Exited With Error";
        const body = body: {
            if (value.timetime_ms > 0) {
                break :body std.fmt.allocPrint(
                    self.alloc,
                    "Child process exited with code {d} after {d} ms.",
                    .{ value.exit_code, value.timetime_ms },
                ) catch return;
            }
            break :body std.fmt.allocPrint(
                self.alloc,
                "Child process exited with code {d}.",
                .{value.exit_code},
            ) catch return;
        };
        defer self.alloc.free(body);

        self.desktopNotification(window, title, body);
    }

    fn commandFinished(
        self: *HostApp,
        window: *Window,
        value: c.ghostty_action_command_finished_s,
    ) void {
        const exit_code: ?u8 = if (value.exit_code >= 0) @intCast(value.exit_code) else null;

        if (window.focused and !window.hidden and (exit_code == null or exit_code.? == 0)) {
            return;
        }

        const title = title: {
            const code = exit_code orelse break :title "Command Finished";
            if (code == 0) break :title "Command Succeeded";
            break :title "Command Failed";
        };
        const duration = formatDurationNs(self.alloc, value.duration) catch return;
        defer self.alloc.free(duration);

        const body = body: {
            if (exit_code) |code| {
                break :body std.fmt.allocPrint(
                    self.alloc,
                    "Command took {s} and exited with code {d}.",
                    .{ duration, code },
                ) catch return;
            }
            break :body std.fmt.allocPrint(
                self.alloc,
                "Command took {s}.",
                .{duration},
            ) catch return;
        };
        defer self.alloc.free(body);

        self.desktopNotification(window, title, body);
    }

    fn promptText(
        self: *HostApp,
        caption: []const u8,
        message: []const u8,
        default_value: []const u8,
    ) ?[]u8 {
        const script = powershellInputBoxScript(
            self.alloc,
            caption,
            message,
            default_value,
        ) catch |err| {
            log.warn("failed to build prompt script err={}", .{err});
            return null;
        };
        defer self.alloc.free(script);

        return self.runPowerShellCapture(script);
    }

    fn runPowerShellDetached(self: *HostApp, script: []const u8) bool {
        const candidates = [_][]const u8{ "powershell.exe", "pwsh.exe" };
        for (candidates) |argv0| {
            var child = std.process.Child.init(
                &.{
                    argv0,
                    "-NoProfile",
                    "-WindowStyle",
                    "Hidden",
                    "-Command",
                    script,
                },
                self.alloc,
            );
            child.stdin_behavior = .Ignore;
            child.stdout_behavior = .Ignore;
            child.stderr_behavior = .Ignore;
            child.spawn() catch continue;
            return true;
        }

        return false;
    }

    fn runPowerShellCapture(self: *HostApp, script: []const u8) ?[]u8 {
        const candidates = [_][]const u8{ "powershell.exe", "pwsh.exe" };
        for (candidates) |argv0| {
            const result = std.process.Child.run(.{
                .allocator = self.alloc,
                .argv = &.{
                    argv0,
                    "-NoProfile",
                    "-STA",
                    "-WindowStyle",
                    "Hidden",
                    "-Command",
                    script,
                },
                .max_output_bytes = 64 * 1024,
            }) catch continue;
            defer self.alloc.free(result.stderr);

            if (result.term != .Exited or result.term.Exited != 0) {
                self.alloc.free(result.stdout);
                continue;
            }

            const trimmed = std.mem.trimRight(u8, result.stdout, "\r\n");
            if (trimmed.len == result.stdout.len) return result.stdout;

            const value = self.alloc.dupe(u8, trimmed) catch {
                self.alloc.free(result.stdout);
                return null;
            };
            self.alloc.free(result.stdout);
            return value;
        }

        return null;
    }
};

const Window = struct {
    host: *HostApp,
    hwnd: win32.HWND = undefined,
    surface: c.ghostty_surface_t = null,
    dpi: u32 = win32.USER_DEFAULT_SCREEN_DPI,
    cursor_id: usize = win32.IDC_IBEAM_ID,
    cursor_visible: bool = true,
    closing: bool = false,
    hidden: bool = false,
    focused: bool = false,
    ime_composing: bool = false,
    decorated: bool = true,
    floating: bool = false,
    fullscreen: bool = false,
    terminal_title: ?[]u8 = null,
    surface_title_override: ?[]u8 = null,
    tab_title_override: ?[]u8 = null,
    pwd: ?[]u8 = null,
    search_needle: ?[]u8 = null,
    search_active: bool = false,
    search_total: ?usize = null,
    search_selected: ?usize = null,
    progress: ?host_state.Progress = null,
    readonly: bool = false,
    default_width: u32 = default_client_width,
    default_height: u32 = default_client_height,
    windowed_rect: win32.RECT = .{
        .left = 0,
        .top = 0,
        .right = 0,
        .bottom = 0,
    },
    has_windowed_rect: bool = false,
    size_limit: SizeLimit = .{},

    const SizeLimit = struct {
        min_width: u32 = 0,
        min_height: u32 = 0,
        max_width: u32 = 0,
        max_height: u32 = 0,
    };

    fn init(
        self: *Window,
        host: *HostApp,
        inherited: ?c.ghostty_surface_config_s,
    ) !void {
        self.* = .{
            .host = host,
        };

        const hwnd = win32.CreateWindowExW(
            window_ex_style,
            class_name,
            default_title,
            window_style,
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            @intCast(default_client_width),
            @intCast(default_client_height),
            null,
            null,
            host.hinstance,
            @ptrCast(self),
        ) orelse return error.CreateWindowFailed;
        self.hwnd = hwnd;
        self.updateDpi();

        var config = inherited orelse c.ghostty_surface_config_new();
        config.platform_tag = c.GHOSTTY_PLATFORM_WINDOWS;
        config.platform.windows.hwnd = @ptrCast(hwnd);
        config.userdata = @ptrCast(self);
        config.scale_factor = self.scaleFactor();

        self.surface = c.ghostty_surface_new(host.app, &config) orelse {
            _ = win32.SetWindowLongPtrW(hwnd, win32.GWLP_USERDATA, 0);
            _ = win32.DestroyWindow(hwnd);
            return error.CreateSurfaceFailed;
        };

        self.syncClientMetrics();
        _ = win32.ShowWindow(hwnd, win32.SW_SHOWDEFAULT);
        _ = win32.UpdateWindow(hwnd);
    }

    fn destroyUntracked(self: *Window) void {
        self.deinitState();
        if (self.surface != null) {
            const surface = self.surface;
            self.surface = null;
            c.ghostty_surface_free(surface);
        }

        _ = win32.SetWindowLongPtrW(self.hwnd, win32.GWLP_USERDATA, 0);
        _ = win32.DestroyWindow(self.hwnd);
    }

    fn onDestroy(self: *Window) void {
        const host = self.host;

        _ = win32.SetWindowLongPtrW(self.hwnd, win32.GWLP_USERDATA, 0);
        self.deinitState();
        if (self.surface != null) {
            const surface = self.surface;
            self.surface = null;
            c.ghostty_surface_free(surface);
        }

        host.removeWindow(self);
        if (host.windows.items.len == 0) win32.PostQuitMessage(0);
        host.alloc.destroy(self);
    }

    fn deinitState(self: *Window) void {
        self.replaceOwnedString(&self.terminal_title, null);
        self.replaceOwnedString(&self.surface_title_override, null);
        self.replaceOwnedString(&self.tab_title_override, null);
        self.replaceOwnedString(&self.pwd, null);
        self.replaceOwnedString(&self.search_needle, null);
    }

    fn replaceOwnedString(self: *Window, slot: *?[]u8, value: ?[]const u8) void {
        if (slot.*) |owned| self.host.alloc.free(owned);
        slot.* = null;

        const next = value orelse return;
        if (next.len == 0) return;
        slot.* = self.host.alloc.dupe(u8, next) catch |err| {
            log.warn("failed to duplicate window state err={}", .{err});
            return;
        };
    }

    fn applyWindowText(self: *Window, title: []const u8) void {
        const wide = std.unicode.utf8ToUtf16LeAllocZ(self.host.alloc, title) catch |err| {
            log.warn("failed to convert title err={}", .{err});
            return;
        };
        defer self.host.alloc.free(wide);

        _ = win32.SetWindowTextW(self.hwnd, wide.ptr);
    }

    fn effectiveTitle(self: *const Window) []const u8 {
        return host_state.effectiveTitle(
            self.terminal_title,
            self.surface_title_override,
            self.tab_title_override,
        );
    }

    fn storedEffectiveTitle(self: *const Window) ?[]const u8 {
        if (self.surface_title_override) |title| {
            if (title.len > 0) return title;
        }
        if (self.tab_title_override) |title| {
            if (title.len > 0) return title;
        }
        if (self.terminal_title) |title| {
            if (title.len > 0) return title;
        }
        return null;
    }

    fn refreshWindowTitle(self: *Window) void {
        const formatted = host_state.formatWindowTitle(self.host.alloc, .{
            .base_title = self.effectiveTitle(),
            .readonly = self.readonly,
            .progress = self.progress,
            .search = .{
                .active = self.search_active,
                .total = self.search_total,
                .selected = self.search_selected,
            },
        }) catch |err| {
            log.warn("failed to format window title err={}", .{err});
            self.applyWindowText(self.effectiveTitle());
            return;
        };
        defer self.host.alloc.free(formatted);

        self.applyWindowText(formatted);
    }

    fn setTerminalTitle(self: *Window, title: []const u8) void {
        self.replaceOwnedString(&self.terminal_title, title);
        self.refreshWindowTitle();
    }

    fn setSurfaceTitleOverride(self: *Window, title: ?[]const u8) void {
        self.replaceOwnedString(&self.surface_title_override, title);
        self.refreshWindowTitle();
    }

    fn setTabTitleOverride(self: *Window, title: []const u8) void {
        self.replaceOwnedString(&self.tab_title_override, title);
        self.refreshWindowTitle();
    }

    fn setPwd(self: *Window, pwd: []const u8) void {
        self.replaceOwnedString(&self.pwd, pwd);
    }

    fn setProgress(self: *Window, progress: c.ghostty_action_progress_report_s) void {
        self.progress = switch (progress.state) {
            c.GHOSTTY_PROGRESS_STATE_REMOVE => null,
            c.GHOSTTY_PROGRESS_STATE_SET => .{
                .state = .set,
                .percent = if (progress.progress >= 0) @intCast(progress.progress) else null,
            },
            c.GHOSTTY_PROGRESS_STATE_ERROR => .{
                .state = .@"error",
                .percent = if (progress.progress >= 0) @intCast(progress.progress) else null,
            },
            c.GHOSTTY_PROGRESS_STATE_INDETERMINATE => .{
                .state = .indeterminate,
                .percent = null,
            },
            c.GHOSTTY_PROGRESS_STATE_PAUSE => .{
                .state = .pause,
                .percent = if (progress.progress >= 0) @intCast(progress.progress) else null,
            },
            else => self.progress,
        };

        if (self.progress) |current| {
            if (current.state == .@"error") self.flash();
        }
        self.refreshWindowTitle();
    }

    fn flash(self: *Window) void {
        var info = win32.FLASHWINFO{
            .hwnd = self.hwnd,
            .dwFlags = win32.FLASHW_TRAY | win32.FLASHW_TIMERNOFG,
            .uCount = 3,
            .dwTimeout = 0,
        };
        _ = win32.FlashWindowEx(&info);
        _ = win32.MessageBeep(0);
    }

    fn updateDpi(self: *Window) void {
        const dpi = win32.GetDpiForWindow(self.hwnd);
        self.dpi = if (dpi == 0) win32.USER_DEFAULT_SCREEN_DPI else dpi;
    }

    fn scaleFactor(self: *const Window) f64 {
        return @as(f64, @floatFromInt(self.dpi)) /
            @as(f64, @floatFromInt(win32.USER_DEFAULT_SCREEN_DPI));
    }

    fn syncClientMetrics(self: *Window) void {
        if (self.surface == null) return;

        self.updateDpi();
        c.ghostty_surface_set_content_scale(
            self.surface,
            self.scaleFactor(),
            self.scaleFactor(),
        );

        var rect: win32.RECT = undefined;
        if (win32.GetClientRect(self.hwnd, &rect) == 0) return;

        const width: u32 = @intCast(@max(rect.right - rect.left, 0));
        const height: u32 = @intCast(@max(rect.bottom - rect.top, 0));
        c.ghostty_surface_set_occlusion(self.surface, width > 0 and height > 0);
        if (width > 0 and height > 0) {
            c.ghostty_surface_set_size(self.surface, width, height);
        }

        if (self.ime_composing) self.updateImeWindow();
    }

    fn setClientSize(self: *Window, width: u32, height: u32) void {
        if (self.fullscreen) return;

        const rect = adjustedRectForStyle(self.frameStyle(), width, height);
        _ = win32.SetWindowPos(
            self.hwnd,
            null,
            0,
            0,
            rect.right - rect.left,
            rect.bottom - rect.top,
            win32.SWP_NOMOVE | win32.SWP_NOZORDER,
        );
    }

    fn frameStyle(self: *const Window) win32.DWORD {
        return host_state.frameStyle(self.decorated, self.fullscreen);
    }

    fn show(self: *Window) void {
        self.hidden = false;
        _ = win32.ShowWindow(self.hwnd, win32.SW_SHOW);
    }

    fn hide(self: *Window) void {
        self.hidden = true;
        _ = win32.ShowWindow(self.hwnd, win32.SW_HIDE);
    }

    fn present(self: *Window) void {
        if (self.hidden) {
            self.hidden = false;
            _ = win32.ShowWindow(self.hwnd, win32.SW_SHOW);
        }
        if (win32.IsIconic(self.hwnd) != 0) {
            _ = win32.ShowWindow(self.hwnd, win32.SW_RESTORE);
        } else {
            _ = win32.ShowWindow(self.hwnd, win32.SW_SHOW);
        }
        _ = win32.SetForegroundWindow(self.hwnd);
    }

    fn promptTitle(self: *Window, target: c.ghostty_action_prompt_title_e) bool {
        const default_value = switch (target) {
            c.GHOSTTY_PROMPT_TITLE_SURFACE => self.surface_title_override orelse self.terminal_title orelse "",
            c.GHOSTTY_PROMPT_TITLE_TAB => self.tab_title_override orelse self.effectiveTitle(),
            else => self.effectiveTitle(),
        };
        const value = self.host.promptText(
            "Ghostty",
            switch (target) {
                c.GHOSTTY_PROMPT_TITLE_SURFACE => prompt_surface_title_message,
                c.GHOSTTY_PROMPT_TITLE_TAB => prompt_tab_title_message,
                else => prompt_surface_title_message,
            },
            default_value,
        ) orelse return false;
        defer self.host.alloc.free(value);

        switch (target) {
            c.GHOSTTY_PROMPT_TITLE_SURFACE => self.setSurfaceTitleOverride(value),
            c.GHOSTTY_PROMPT_TITLE_TAB => self.setTabTitleOverride(value),
            else => self.setSurfaceTitleOverride(value),
        }
        return true;
    }

    fn startSearch(self: *Window, needle: []const u8) bool {
        const default_value = if (needle.len > 0) needle else self.search_needle orelse "";
        const value = self.host.promptText(
            "Ghostty Search",
            prompt_search_message,
            default_value,
        ) orelse return false;
        defer self.host.alloc.free(value);

        self.search_active = true;
        self.replaceOwnedString(&self.search_needle, value);
        self.search_total = null;
        self.search_selected = null;
        self.refreshWindowTitle();

        if (self.surface == null) return true;

        if (value.len == 0) {
            self.endSearch();
            return c.ghostty_surface_binding_action(self.surface, "end_search", "end_search".len);
        }

        const action = std.fmt.allocPrint(self.host.alloc, "search:{s}", .{value}) catch |err| {
            log.warn("failed to format search action err={}", .{err});
            return false;
        };
        defer self.host.alloc.free(action);

        return c.ghostty_surface_binding_action(self.surface, action.ptr, action.len);
    }

    fn endSearch(self: *Window) void {
        self.search_active = false;
        self.search_total = null;
        self.search_selected = null;
        self.replaceOwnedString(&self.search_needle, null);
        self.refreshWindowTitle();
    }

    fn copyTitleToClipboard(self: *Window) bool {
        const title = self.storedEffectiveTitle() orelse return false;
        return writeClipboardText(self.hwnd, self.host.alloc, title);
    }

    fn resetSize(self: *Window) void {
        if (self.fullscreen) self.toggleFullscreen(c.GHOSTTY_FULLSCREEN_NATIVE);
        if (win32.IsZoomed(self.hwnd) != 0) {
            _ = win32.ShowWindow(self.hwnd, win32.SW_RESTORE);
        }

        self.setClientSize(self.default_width, self.default_height);
    }

    fn toggleMaximize(self: *Window) void {
        if (self.fullscreen) self.toggleFullscreen(c.GHOSTTY_FULLSCREEN_NATIVE);
        if (win32.IsZoomed(self.hwnd) != 0) {
            _ = win32.ShowWindow(self.hwnd, win32.SW_RESTORE);
        } else {
            _ = win32.ShowWindow(self.hwnd, win32.SW_MAXIMIZE);
        }
    }

    fn toggleFullscreen(self: *Window, mode: c.ghostty_action_fullscreen_e) void {
        _ = mode;

        if (self.fullscreen) {
            self.fullscreen = false;
            const rect = if (self.has_windowed_rect)
                self.windowed_rect
            else
                adjustedRectForStyle(
                    if (self.decorated) window_style else borderless_window_style,
                    self.default_width,
                    self.default_height,
                );
            self.applyFrame(rect);
            return;
        }

        if (win32.GetWindowRect(self.hwnd, &self.windowed_rect) != 0) {
            self.has_windowed_rect = true;
        }

        const monitor = win32.MonitorFromWindow(self.hwnd, win32.MONITOR_DEFAULTTONEAREST) orelse return;

        var info = std.mem.zeroes(win32.MONITORINFO);
        info.cbSize = @sizeOf(win32.MONITORINFO);
        if (win32.GetMonitorInfoW(monitor, &info) == 0) return;

        self.fullscreen = true;
        self.applyFrame(info.rcMonitor);
    }

    fn toggleWindowDecorations(self: *Window) void {
        self.decorated = !self.decorated;
        if (self.fullscreen) return;

        var rect: win32.RECT = undefined;
        if (win32.GetWindowRect(self.hwnd, &rect) == 0) return;
        self.applyFrame(rect);
    }

    fn setFloating(self: *Window, mode: c.ghostty_action_float_window_e) void {
        const next = switch (mode) {
            c.GHOSTTY_FLOAT_WINDOW_ON => true,
            c.GHOSTTY_FLOAT_WINDOW_OFF => false,
            c.GHOSTTY_FLOAT_WINDOW_TOGGLE => !self.floating,
            else => self.floating,
        };
        if (self.floating == next) return;

        self.floating = next;
        self.applyFloating();
    }

    fn applyFloating(self: *Window) void {
        _ = win32.SetWindowPos(
            self.hwnd,
            if (self.floating) win32.HWND_TOPMOST else win32.HWND_NOTOPMOST,
            0,
            0,
            0,
            0,
            win32.SWP_NOMOVE | win32.SWP_NOSIZE,
        );
    }

    fn applyFrame(self: *Window, rect: win32.RECT) void {
        _ = win32.SetWindowLongPtrW(
            self.hwnd,
            win32.GWLP_STYLE,
            @intCast(self.frameStyle()),
        );
        _ = win32.SetWindowPos(
            self.hwnd,
            null,
            rect.left,
            rect.top,
            rect.right - rect.left,
            rect.bottom - rect.top,
            win32.SWP_FRAMECHANGED | win32.SWP_NOZORDER,
        );
        self.applyFloating();
    }

    fn imeOpen(self: *Window) bool {
        const ime = win32.ImmGetContext(self.hwnd) orelse return false;
        defer _ = win32.ImmReleaseContext(self.hwnd, ime);
        return win32.ImmGetOpenStatus(ime) != 0;
    }

    fn updateImeWindow(self: *Window) void {
        if (self.surface == null) return;

        const ime = win32.ImmGetContext(self.hwnd) orelse return;
        defer _ = win32.ImmReleaseContext(self.hwnd, ime);

        var x: f64 = 0;
        var y: f64 = 0;
        var width: f64 = 0;
        var height: f64 = 0;
        c.ghostty_surface_ime_point(self.surface, &x, &y, &width, &height);

        const point = win32.POINT{
            .x = @intFromFloat(x),
            .y = @intFromFloat(y),
        };
        const rect = host_state.imeExcludeRect(x, y, width, height);

        const composition = win32.COMPOSITIONFORM{
            .dwStyle = win32.CFS_POINT,
            .ptCurrentPos = point,
            .rcArea = .{
                .left = 0,
                .top = 0,
                .right = 0,
                .bottom = 0,
            },
        };
        _ = win32.ImmSetCompositionWindow(ime, &composition);

        const candidate = win32.CANDIDATEFORM{
            .dwIndex = 0,
            .dwStyle = win32.CFS_EXCLUDE,
            .ptCurrentPos = point,
            .rcArea = rect,
        };
        _ = win32.ImmSetCandidateWindow(ime, &candidate);
    }

    fn compositionStringUtf8(
        self: *Window,
        ime: win32.HIMC,
        kind: win32.DWORD,
    ) ?[]u8 {
        const bytes = win32.ImmGetCompositionStringW(ime, kind, null, 0);
        if (bytes <= 0) return null;

        const byte_len: usize = @intCast(bytes);
        const wide_len = byte_len / @sizeOf(u16);
        const wide = self.host.alloc.alloc(u16, wide_len) catch |err| {
            log.warn("failed to allocate ime buffer err={}", .{err});
            return null;
        };
        defer self.host.alloc.free(wide);

        const copied = win32.ImmGetCompositionStringW(
            ime,
            kind,
            @ptrCast(wide.ptr),
            @intCast(byte_len),
        );
        if (copied <= 0) return null;

        return std.unicode.utf16LeToUtf8Alloc(self.host.alloc, wide) catch |err| {
            log.warn("failed to convert ime text err={}", .{err});
            return null;
        };
    }

    fn handleImeComposition(self: *Window, lParam: win32.LPARAM) void {
        if (self.surface == null) return;

        const flags: win32.DWORD = @truncate(@as(usize, @bitCast(lParam)));
        const ime = win32.ImmGetContext(self.hwnd) orelse return;
        defer _ = win32.ImmReleaseContext(self.hwnd, ime);

        self.updateImeWindow();

        if ((flags & win32.GCS_RESULTSTR) != 0) {
            const text = self.compositionStringUtf8(ime, win32.GCS_RESULTSTR) orelse "";
            defer if (text.len > 0) self.host.alloc.free(text);

            if (text.len > 0) c.ghostty_surface_text(self.surface, text.ptr, text.len);
        }

        if ((flags & win32.GCS_COMPSTR) != 0) {
            const preedit = self.compositionStringUtf8(ime, win32.GCS_COMPSTR) orelse "";
            defer if (preedit.len > 0) self.host.alloc.free(preedit);

            self.ime_composing = preedit.len > 0;
            c.ghostty_surface_preedit(
                self.surface,
                if (preedit.len > 0) preedit.ptr else null,
                preedit.len,
            );
            return;
        }

        if ((flags & win32.GCS_RESULTSTR) != 0) {
            self.ime_composing = false;
            c.ghostty_surface_preedit(self.surface, null, 0);
        }
    }

    fn applyCursor(self: *Window) void {
        if (!self.cursor_visible) {
            _ = win32.SetCursor(null);
            return;
        }

        _ = win32.SetCursor(win32.loadSystemCursor(self.cursor_id));
    }

    fn updateCapture(self: *Window) void {
        if (self.surface == null) return;
        if (c.ghostty_surface_mouse_captured(self.surface)) {
            _ = win32.SetCapture(self.hwnd);
        } else {
            _ = win32.ReleaseCapture();
        }
    }

    fn handleKey(self: *Window, action: c.ghostty_input_action_e, wParam: win32.WPARAM, lParam: win32.LPARAM) void {
        if (self.surface == null) return;

        const vk: c_uint = @intCast(wParam);
        const scan_raw = rawScanCode(lParam);
        const ime_open = action != c.GHOSTTY_ACTION_RELEASE and self.imeOpen();
        var text_buf: [17]u8 = [_]u8{0} ** 17;
        const text_len = if (action == c.GHOSTTY_ACTION_RELEASE or ime_open)
            0
        else
            fillKeyText(vk, scan_raw, text_buf[0 .. text_buf.len - 1]);

        var event = std.mem.zeroInit(c.ghostty_input_key_s, .{});
        event.action = action;
        event.mods = keyboardMods();
        event.consumed_mods = 0;
        event.keycode = nativeKeyCode(lParam);
        event.text = if (text_len > 0) @ptrCast(&text_buf[0]) else null;
        event.unshifted_codepoint = unshiftedCodepoint(vk) orelse if (text_len > 0)
            std.unicode.utf8Decode(text_buf[0..text_len]) catch 0
        else
            0;
        event.composing = self.ime_composing or ime_open;

        _ = c.ghostty_surface_key(self.surface, event);
        if (self.ime_composing or ime_open) self.updateImeWindow();
    }

    fn handleMouseButton(
        self: *Window,
        button: c.ghostty_input_mouse_button_e,
        state: c.ghostty_input_mouse_state_e,
        lParam: win32.LPARAM,
    ) void {
        if (self.surface == null) return;

        const mods = keyboardMods();
        c.ghostty_surface_mouse_pos(
            self.surface,
            @floatCast(win32.getXLparam(lParam)),
            @floatCast(win32.getYLparam(lParam)),
            mods,
        );
        _ = c.ghostty_surface_mouse_button(self.surface, state, button, mods);
        self.updateCapture();
        if (self.ime_composing) self.updateImeWindow();
    }
};

fn registerWindowClass(hinstance: win32.HINSTANCE) !void {
    if (class_registered) return;

    const wc = win32.WNDCLASSEXW{
        .style = 0x0003,
        .lpfnWndProc = wndProc,
        .hInstance = hinstance,
        .hCursor = win32.loadSystemCursor(win32.IDC_IBEAM_ID),
        .lpszClassName = class_name,
    };

    if (win32.RegisterClassExW(&wc) == 0) return error.RegisterClassFailed;
    class_registered = true;
}

fn loadConfig() !c.ghostty_config_t {
    const config = c.ghostty_config_new() orelse
        return error.CreateConfigFailed;
    errdefer c.ghostty_config_free(config);

    c.ghostty_config_load_default_files(config);
    c.ghostty_config_load_cli_args(config);
    c.ghostty_config_load_recursive_files(config);
    c.ghostty_config_finalize(config);
    return config;
}

fn runtimeWakeup(userdata: ?*anyopaque) callconv(.c) void {
    const host = hostFromUserdata(userdata) orelse return;
    if (host.windows.items.len == 0) return;
    _ = win32.PostMessageW(host.windows.items[0].hwnd, win32.WM_APP_WAKEUP, 0, 0);
}

fn runtimeAction(
    app: c.ghostty_app_t,
    target: c.ghostty_target_s,
    action: c.ghostty_action_s,
) callconv(.c) bool {
    const host = hostFromApp(app) orelse return false;
    return host.handleAction(target, action);
}

fn runtimeReadClipboard(
    userdata: ?*anyopaque,
    clipboard: c.ghostty_clipboard_e,
    state: ?*anyopaque,
) callconv(.c) bool {
    const window = windowFromUserdata(userdata) orelse return false;
    if (window.surface == null or clipboard != c.GHOSTTY_CLIPBOARD_STANDARD) return false;

    if (win32.OpenClipboard(window.hwnd) == 0) return false;
    defer _ = win32.CloseClipboard();

    const handle = win32.GetClipboardData(win32.CF_UNICODETEXT) orelse return false;
    const ptr = win32.GlobalLock(handle) orelse return false;
    defer _ = win32.GlobalUnlock(handle);

    const wide: [*:0]const u16 = @ptrCast(@alignCast(ptr));
    const utf8 = win32.utf16ToUtf8(window.host.alloc, wide) catch return false;
    defer window.host.alloc.free(utf8);

    const utf8z = window.host.alloc.dupeZ(u8, utf8) catch return false;
    defer window.host.alloc.free(utf8z);

    c.ghostty_surface_complete_clipboard_request(
        window.surface,
        utf8z.ptr,
        state,
        true,
    );
    return true;
}

fn runtimeConfirmReadClipboard(
    userdata: ?*anyopaque,
    text: [*c]const u8,
    state: ?*anyopaque,
    kind: c.ghostty_clipboard_request_e,
) callconv(.c) void {
    _ = kind;
    const window = windowFromUserdata(userdata) orelse return;
    if (window.surface == null) return;

    const result = win32.MessageBoxW(
        window.hwnd,
        clipboard_prompt,
        prompt_title,
        win32.MB_OKCANCEL | win32.MB_ICONWARNING,
    );
    c.ghostty_surface_complete_clipboard_request(
        window.surface,
        text,
        state,
        result == win32.IDOK,
    );
}

fn runtimeWriteClipboard(
    userdata: ?*anyopaque,
    clipboard: c.ghostty_clipboard_e,
    contents: [*c]const c.ghostty_clipboard_content_s,
    len: usize,
    confirm: bool,
) callconv(.c) void {
    _ = confirm;
    const window = windowFromUserdata(userdata) orelse return;
    if (clipboard != c.GHOSTTY_CLIPBOARD_STANDARD) return;

    var text: ?[]const u8 = null;
    for (contents[0..len]) |content| {
        const mime = std.mem.span(content.mime);
        if (std.mem.eql(u8, mime, "text/plain") or
            std.mem.startsWith(u8, mime, "text/"))
        {
            text = std.mem.span(content.data);
            break;
        }
    }

    const data = text orelse return;
    _ = writeClipboardText(window.hwnd, window.host.alloc, data);
}

fn runtimeCloseSurface(userdata: ?*anyopaque, process_alive: bool) callconv(.c) void {
    _ = process_alive;
    const window = windowFromUserdata(userdata) orelse return;
    _ = win32.PostMessageW(window.hwnd, WM_APP_CLOSE, 0, 0);
}

fn writeClipboardText(hwnd: win32.HWND, alloc: Allocator, data: []const u8) bool {
    const wide = std.unicode.utf8ToUtf16LeAlloc(alloc, data) catch return false;
    defer alloc.free(wide);

    const size = (wide.len + 1) * @sizeOf(u16);
    const handle = win32.GlobalAlloc(win32.GMEM_MOVEABLE, size) orelse return false;
    const ptr = win32.GlobalLock(handle) orelse return false;
    defer _ = win32.GlobalUnlock(handle);

    const dest: [*]u16 = @ptrCast(@alignCast(ptr));
    @memcpy(dest[0..wide.len], wide);
    dest[wide.len] = 0;

    if (win32.OpenClipboard(hwnd) == 0) return false;
    defer _ = win32.CloseClipboard();
    _ = win32.EmptyClipboard();
    _ = win32.SetClipboardData(win32.CF_UNICODETEXT, handle);
    return true;
}

fn formatDurationNs(alloc: Allocator, duration_ns: u64) ![]u8 {
    if (duration_ns >= std.time.ns_per_s) {
        const seconds = duration_ns / std.time.ns_per_s;
        const tenths = (duration_ns % std.time.ns_per_s) / (std.time.ns_per_s / 10);
        return std.fmt.allocPrint(alloc, "{d}.{d}s", .{ seconds, tenths });
    }
    if (duration_ns >= std.time.ns_per_ms) {
        return std.fmt.allocPrint(alloc, "{d}ms", .{duration_ns / std.time.ns_per_ms});
    }
    if (duration_ns >= std.time.ns_per_us) {
        return std.fmt.allocPrint(alloc, "{d}us", .{duration_ns / std.time.ns_per_us});
    }
    return std.fmt.allocPrint(alloc, "{d}ns", .{duration_ns});
}

fn powershellInputBoxScript(
    alloc: Allocator,
    caption: []const u8,
    message: []const u8,
    default_value: []const u8,
) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(alloc);
    const writer = list.writer(alloc);

    try writer.writeAll("$ErrorActionPreference='Stop'; Add-Type -AssemblyName Microsoft.VisualBasic; [Console]::OutputEncoding=[System.Text.Encoding]::UTF8; [Console]::Out.Write([Microsoft.VisualBasic.Interaction]::InputBox(");
    try appendPowerShellSingleQuoted(writer, message);
    try writer.writeAll(", ");
    try appendPowerShellSingleQuoted(writer, caption);
    try writer.writeAll(", ");
    try appendPowerShellSingleQuoted(writer, default_value);
    try writer.writeAll("))");

    return list.toOwnedSlice(alloc);
}

fn powershellBalloonScript(
    alloc: Allocator,
    title: []const u8,
    body: []const u8,
) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(alloc);
    const writer = list.writer(alloc);

    try writer.writeAll("$ErrorActionPreference='Stop'; Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; $notify=New-Object System.Windows.Forms.NotifyIcon; $notify.Icon=[System.Drawing.SystemIcons]::Application; $notify.BalloonTipTitle=");
    try appendPowerShellSingleQuoted(writer, title);
    try writer.writeAll("; $notify.BalloonTipText=");
    try appendPowerShellSingleQuoted(writer, body);
    try writer.writeAll("; $notify.Visible=$true; $notify.ShowBalloonTip(5000); Start-Sleep -Milliseconds 5500; $notify.Dispose()");

    return list.toOwnedSlice(alloc);
}

fn appendPowerShellSingleQuoted(writer: anytype, value: []const u8) !void {
    try writer.writeByte('\'');
    for (value) |ch| {
        if (ch == '\'') {
            try writer.writeAll("''");
        } else {
            try writer.writeByte(ch);
        }
    }
    try writer.writeByte('\'');
}

fn wndProc(
    hwnd: win32.HWND,
    msg: win32.UINT,
    wParam: win32.WPARAM,
    lParam: win32.LPARAM,
) callconv(.c) win32.LRESULT {
    if (msg == win32.WM_NCCREATE) {
        const cs: *const win32.CREATESTRUCTW = @ptrFromInt(@as(usize, @bitCast(lParam)));
        const window: *Window = @ptrCast(@alignCast(cs.lpCreateParams.?));
        window.hwnd = hwnd;
        _ = win32.SetWindowLongPtrW(hwnd, win32.GWLP_USERDATA, @bitCast(@intFromPtr(window)));
        return 1;
    }

    const window = getWindow(hwnd) orelse
        return win32.DefWindowProcW(hwnd, msg, wParam, lParam);

    switch (msg) {
        win32.WM_APP_WAKEUP => {
            c.ghostty_app_tick(window.host.app);
            return 0;
        },

        WM_APP_CLOSE => {
            if (!window.closing) {
                window.closing = true;
                _ = win32.DestroyWindow(hwnd);
            }
            return 0;
        },

        win32.WM_PAINT => {
            if (window.surface != null) c.ghostty_surface_draw(window.surface);
            _ = win32.ValidateRect(hwnd, null);
            return 0;
        },

        win32.WM_ERASEBKGND => return 1,

        win32.WM_SIZE => {
            window.syncClientMetrics();
            return 0;
        },

        win32.WM_DPICHANGED => {
            window.updateDpi();
            if (window.surface != null) {
                c.ghostty_surface_set_content_scale(
                    window.surface,
                    window.scaleFactor(),
                    window.scaleFactor(),
                );
            }

            const rect: *const win32.RECT = @ptrFromInt(@as(usize, @bitCast(lParam)));
            _ = win32.SetWindowPos(
                hwnd,
                null,
                rect.left,
                rect.top,
                rect.right - rect.left,
                rect.bottom - rect.top,
                win32.SWP_NOZORDER,
            );
            if (window.ime_composing) window.updateImeWindow();
            return 0;
        },

        win32.WM_GETMINMAXINFO => {
            const info: *win32.MINMAXINFO = @ptrFromInt(@as(usize, @bitCast(lParam)));
            applySizeLimit(window.size_limit, window.frameStyle(), info);
            return 0;
        },

        win32.WM_SETFOCUS => {
            window.focused = true;
            if (window.surface != null) c.ghostty_surface_set_focus(window.surface, true);
            window.updateImeWindow();
            return 0;
        },

        win32.WM_KILLFOCUS => {
            window.focused = false;
            if (window.surface != null) {
                c.ghostty_surface_set_focus(window.surface, false);
                c.ghostty_surface_preedit(window.surface, null, 0);
            }
            window.ime_composing = false;
            return 0;
        },

        win32.WM_SETCURSOR => {
            if (@as(u16, @bitCast(win32.loword(lParam))) == win32.HTCLIENT) {
                window.applyCursor();
                return 1;
            }
        },

        win32.WM_KEYDOWN, win32.WM_SYSKEYDOWN => {
            const action: c.ghostty_input_action_e = if (((@as(usize, @bitCast(lParam)) >> 30) & 1) != 0)
                c.GHOSTTY_ACTION_REPEAT
            else
                c.GHOSTTY_ACTION_PRESS;
            window.handleKey(action, wParam, lParam);
            return 0;
        },

        win32.WM_KEYUP, win32.WM_SYSKEYUP => {
            window.handleKey(c.GHOSTTY_ACTION_RELEASE, wParam, lParam);
            return 0;
        },

        win32.WM_CHAR => return 0,

        win32.WM_IME_STARTCOMPOSITION => {
            window.ime_composing = true;
            window.updateImeWindow();
            return 0;
        },

        win32.WM_IME_COMPOSITION => {
            window.handleImeComposition(lParam);
            return 0;
        },

        win32.WM_IME_ENDCOMPOSITION => {
            window.ime_composing = false;
            if (window.surface != null) c.ghostty_surface_preedit(window.surface, null, 0);
            return 0;
        },

        win32.WM_MOUSEMOVE => {
            if (window.surface != null) {
                c.ghostty_surface_mouse_pos(
                    window.surface,
                    @floatCast(win32.getXLparam(lParam)),
                    @floatCast(win32.getYLparam(lParam)),
                    keyboardMods(),
                );
            }
            if (window.ime_composing) window.updateImeWindow();
            return 0;
        },

        win32.WM_LBUTTONDOWN => {
            window.handleMouseButton(c.GHOSTTY_MOUSE_LEFT, c.GHOSTTY_MOUSE_PRESS, lParam);
            return 0;
        },

        win32.WM_LBUTTONUP => {
            window.handleMouseButton(c.GHOSTTY_MOUSE_LEFT, c.GHOSTTY_MOUSE_RELEASE, lParam);
            return 0;
        },

        win32.WM_RBUTTONDOWN => {
            window.handleMouseButton(c.GHOSTTY_MOUSE_RIGHT, c.GHOSTTY_MOUSE_PRESS, lParam);
            return 0;
        },

        win32.WM_RBUTTONUP => {
            window.handleMouseButton(c.GHOSTTY_MOUSE_RIGHT, c.GHOSTTY_MOUSE_RELEASE, lParam);
            return 0;
        },

        win32.WM_MBUTTONDOWN => {
            window.handleMouseButton(c.GHOSTTY_MOUSE_MIDDLE, c.GHOSTTY_MOUSE_PRESS, lParam);
            return 0;
        },

        win32.WM_MBUTTONUP => {
            window.handleMouseButton(c.GHOSTTY_MOUSE_MIDDLE, c.GHOSTTY_MOUSE_RELEASE, lParam);
            return 0;
        },

        win32.WM_MOUSEWHEEL => {
            if (window.surface != null) {
                const delta = win32.hiwordW(wParam);
                c.ghostty_surface_mouse_scroll(
                    window.surface,
                    0,
                    @as(f64, @floatFromInt(delta)) / 120.0,
                    0,
                );
            }
            return 0;
        },

        win32.WM_MOUSEHWHEEL => {
            if (window.surface != null) {
                const delta = win32.hiwordW(wParam);
                c.ghostty_surface_mouse_scroll(
                    window.surface,
                    @as(f64, @floatFromInt(delta)) / 120.0,
                    0,
                    0,
                );
            }
            return 0;
        },

        win32.WM_CLOSE => {
            if (window.surface != null) {
                c.ghostty_surface_request_close(window.surface);
            } else {
                _ = win32.DestroyWindow(hwnd);
            }
            return 0;
        },

        win32.WM_DESTROY => {
            window.onDestroy();
            return 0;
        },

        else => {},
    }

    return win32.DefWindowProcW(hwnd, msg, wParam, lParam);
}

fn applySizeLimit(limit: Window.SizeLimit, style: win32.DWORD, info: *win32.MINMAXINFO) void {
    if (limit.min_width > 0 or limit.min_height > 0) {
        const rect = adjustedRectForStyle(style, limit.min_width, limit.min_height);
        info.ptMinTrackSize.x = rect.right - rect.left;
        info.ptMinTrackSize.y = rect.bottom - rect.top;
    }

    if (limit.max_width > 0 or limit.max_height > 0) {
        const rect = adjustedRectForStyle(style, limit.max_width, limit.max_height);
        info.ptMaxTrackSize.x = rect.right - rect.left;
        info.ptMaxTrackSize.y = rect.bottom - rect.top;
    }
}

fn adjustedRectForStyle(style: win32.DWORD, width: u32, height: u32) win32.RECT {
    var rect = win32.RECT{
        .left = 0,
        .top = 0,
        .right = @intCast(width),
        .bottom = @intCast(height),
    };
    _ = win32.AdjustWindowRectEx(&rect, style, 0, window_ex_style);
    return rect;
}

fn cursorId(shape: c.ghostty_action_mouse_shape_e) usize {
    return switch (shape) {
        c.GHOSTTY_MOUSE_SHAPE_TEXT,
        c.GHOSTTY_MOUSE_SHAPE_VERTICAL_TEXT,
        => win32.IDC_IBEAM_ID,

        c.GHOSTTY_MOUSE_SHAPE_POINTER,
        c.GHOSTTY_MOUSE_SHAPE_COPY,
        c.GHOSTTY_MOUSE_SHAPE_ALIAS,
        c.GHOSTTY_MOUSE_SHAPE_ZOOM_IN,
        c.GHOSTTY_MOUSE_SHAPE_ZOOM_OUT,
        => win32.IDC_HAND_ID,

        c.GHOSTTY_MOUSE_SHAPE_WAIT,
        c.GHOSTTY_MOUSE_SHAPE_PROGRESS,
        => win32.IDC_WAIT_ID,

        c.GHOSTTY_MOUSE_SHAPE_MOVE,
        c.GHOSTTY_MOUSE_SHAPE_ALL_SCROLL,
        => win32.IDC_SIZEALL_ID,

        c.GHOSTTY_MOUSE_SHAPE_COL_RESIZE,
        c.GHOSTTY_MOUSE_SHAPE_E_RESIZE,
        c.GHOSTTY_MOUSE_SHAPE_W_RESIZE,
        c.GHOSTTY_MOUSE_SHAPE_EW_RESIZE,
        => win32.IDC_SIZEWE_ID,

        c.GHOSTTY_MOUSE_SHAPE_ROW_RESIZE,
        c.GHOSTTY_MOUSE_SHAPE_N_RESIZE,
        c.GHOSTTY_MOUSE_SHAPE_S_RESIZE,
        c.GHOSTTY_MOUSE_SHAPE_NS_RESIZE,
        => win32.IDC_SIZENS_ID,

        c.GHOSTTY_MOUSE_SHAPE_NO_DROP,
        c.GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED,
        => win32.IDC_NO_ID,

        else => win32.IDC_ARROW_ID,
    };
}

fn keyboardMods() c.ghostty_input_mods_e {
    var raw: c_uint = 0;

    if (win32.GetKeyState(win32.VK_SHIFT) < 0) raw |= @intCast(c.GHOSTTY_MODS_SHIFT);
    if (win32.GetKeyState(win32.VK_CONTROL) < 0) raw |= @intCast(c.GHOSTTY_MODS_CTRL);
    if (win32.GetKeyState(win32.VK_MENU) < 0) raw |= @intCast(c.GHOSTTY_MODS_ALT);
    if (win32.GetKeyState(win32.VK_LWIN) < 0 or win32.GetKeyState(win32.VK_RWIN) < 0) raw |= @intCast(c.GHOSTTY_MODS_SUPER);
    if ((win32.GetKeyState(win32.VK_CAPITAL) & 1) != 0) raw |= @intCast(c.GHOSTTY_MODS_CAPS);
    if ((win32.GetKeyState(win32.VK_NUMLOCK) & 1) != 0) raw |= @intCast(c.GHOSTTY_MODS_NUM);
    if (win32.GetKeyState(win32.VK_RSHIFT) < 0) raw |= @intCast(c.GHOSTTY_MODS_SHIFT_RIGHT);
    if (win32.GetKeyState(win32.VK_RCONTROL) < 0) raw |= @intCast(c.GHOSTTY_MODS_CTRL_RIGHT);
    if (win32.GetKeyState(win32.VK_RMENU) < 0) raw |= @intCast(c.GHOSTTY_MODS_ALT_RIGHT);
    if (win32.GetKeyState(win32.VK_RWIN) < 0) raw |= @intCast(c.GHOSTTY_MODS_SUPER_RIGHT);

    return raw;
}

fn rawScanCode(lParam: win32.LPARAM) c_uint {
    return @truncate((@as(usize, @bitCast(lParam)) >> 16) & 0xFF);
}

fn nativeKeyCode(lParam: win32.LPARAM) u32 {
    const raw = @as(usize, @bitCast(lParam));
    var scan: u32 = @truncate((raw >> 16) & 0xFF);
    if (((raw >> 24) & 1) != 0) scan |= 0xE000;
    return scan;
}

fn fillKeyText(vk: c_uint, scan_code: c_uint, buf: []u8) usize {
    var keyboard_state: [256]win32.BYTE = undefined;
    if (win32.GetKeyboardState(&keyboard_state) == 0) return 0;

    var utf16_buf: [4]u16 = undefined;
    const result = win32.ToUnicodeEx(
        vk,
        scan_code,
        &keyboard_state,
        &utf16_buf,
        @intCast(utf16_buf.len),
        0,
        null,
    );
    if (result <= 0) return 0;

    return std.unicode.utf16LeToUtf8(buf, utf16_buf[0..@intCast(result)]) catch 0;
}

fn unshiftedCodepoint(vk: c_uint) ?u32 {
    return switch (vk) {
        win32.VK_BACK => 0x08,
        win32.VK_TAB => 0x09,
        win32.VK_RETURN => 0x0D,
        win32.VK_SPACE => ' ',
        else => mapped: {
            const mapped = win32.MapVirtualKeyW(vk, win32.MAPVK_VK_TO_CHAR);
            if (mapped == 0) break :mapped null;

            const codepoint = mapped & 0x7FFF;
            if (codepoint == 0) break :mapped null;
            break :mapped if (codepoint >= 'A' and codepoint <= 'Z')
                codepoint + ('a' - 'A')
            else
                codepoint;
        },
    };
}

fn getWindow(hwnd: win32.HWND) ?*Window {
    const ptr = win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA);
    if (ptr == 0) return null;
    return @ptrFromInt(@as(usize, @bitCast(ptr)));
}

fn hostFromApp(app: c.ghostty_app_t) ?*HostApp {
    return hostFromUserdata(c.ghostty_app_userdata(app));
}

fn hostFromUserdata(userdata: ?*anyopaque) ?*HostApp {
    const ptr = userdata orelse return null;
    return @ptrCast(@alignCast(ptr));
}

fn windowFromUserdata(userdata: ?*anyopaque) ?*Window {
    const ptr = userdata orelse return null;
    return @ptrCast(@alignCast(ptr));
}

fn windowFromSurface(surface: c.ghostty_surface_t) ?*Window {
    return windowFromUserdata(c.ghostty_surface_userdata(surface));
}

fn targetWindow(target: c.ghostty_target_s) ?*Window {
    if (target.tag != c.GHOSTTY_TARGET_SURFACE) return null;
    return windowFromSurface(target.target.surface);
}
