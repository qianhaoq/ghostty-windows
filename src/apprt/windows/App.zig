/// Win32 application runtime for Ghostty on Windows.
/// Provides native windowing using the Win32 API with WGL for OpenGL rendering.
const App = @This();

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const apprt = @import("../../apprt.zig");
const configpkg = @import("../../config.zig");
const CoreApp = @import("../../App.zig");
const CoreSurface = @import("../../Surface.zig");

const Surface = @import("Surface.zig");
const win32 = @import("win32.zig");

const log = std.log.scoped(.win32);

pub const class_name = std.unicode.utf8ToUtf16LeStringLiteral("GhosttyWindow");

/// The core application instance.
core_app: *CoreApp,

/// All active surfaces.
surfaces: std.ArrayListUnmanaged(*Surface) = .{},

/// Allocator for surface management.
alloc: Allocator,

/// Whether the app is running.
running: bool = false,

/// Win32 window class atom.
wnd_class: win32.ATOM = 0,

/// HINSTANCE for the application.
hinstance: win32.HINSTANCE,

pub fn init(
    self: *App,
    core_app: *CoreApp,
    opts: struct {},
) !void {
    _ = opts;

    const hinstance = win32.GetModuleHandleW(null) orelse
        return error.GetModuleHandleFailed;

    // Register the window class
    const wc = win32.WNDCLASSEXW{
        .style = 0x0003, // CS_HREDRAW | CS_VREDRAW
        .lpfnWndProc = Surface.wndProc,
        .hInstance = hinstance,
        .hCursor = win32.loadSystemCursor(win32.IDC_IBEAM_ID),
        .lpszClassName = class_name,
    };

    const atom = win32.RegisterClassExW(&wc);
    if (atom == 0) return error.RegisterClassFailed;

    self.* = .{
        .core_app = core_app,
        .alloc = core_app.alloc,
        .hinstance = hinstance,
        .wnd_class = atom,
    };

    log.info("Win32 app runtime initialized", .{});
}

pub fn run(self: *App) !void {
    self.running = true;

    // Create the initial window
    try self.newWindow();

    // Main message loop
    var msg: win32.MSG = undefined;
    while (self.running) {
        // Process all pending messages
        while (win32.PeekMessageW(&msg, null, 0, 0, win32.PM_REMOVE) != 0) {
            if (msg.message == win32.WM_QUIT) {
                self.running = false;
                break;
            }
            _ = win32.TranslateMessage(&msg);
            _ = win32.DispatchMessageW(&msg);
        }

        if (!self.running) break;

        // Tick the core app to drain its mailbox
        self.core_app.tick(self) catch |err| {
            log.err("core app tick error: {}", .{err});
        };

        // If no surfaces remain, quit
        if (self.surfaces.items.len == 0) {
            self.running = false;
        }

        // Yield to avoid busy-waiting
        std.Thread.sleep(1 * std.time.ns_per_ms);
    }

    log.info("Win32 message loop exited", .{});
}

pub fn terminate(self: *App) void {
    self.running = false;
    self.closeAllWindows();
    self.surfaces.deinit(self.alloc);
    log.info("Win32 app runtime terminated", .{});
}

pub fn wakeup(self: *App) void {
    // Post a custom message to wake the message loop.
    // We need to send it to one of our windows.
    if (self.surfaces.items.len > 0) {
        _ = win32.PostMessageW(self.surfaces.items[0].hwnd, win32.WM_APP_WAKEUP, 0, 0);
    }
}

pub fn performAction(
    self: *App,
    target: apprt.Target,
    comptime action: apprt.Action.Key,
    value: apprt.Action.Value(action),
) !bool {
    switch (action) {
        .new_window => {
            try self.newWindow();
            return true;
        },

        .set_title => {
            switch (target) {
                .surface => |surface| {
                    const rt_surface = surface.rt_surface;
                    const title_w = try std.unicode.utf8ToUtf16LeAllocZ(
                        self.alloc,
                        value.title,
                    );
                    defer self.alloc.free(title_w);

                    if (rt_surface.title) |title| self.alloc.free(title);
                    rt_surface.title = try self.alloc.dupeZ(u8, value.title);
                    _ = win32.SetWindowTextW(rt_surface.hwnd, title_w.ptr);
                },
                .app => {},
            }
            return true;
        },

        .render => {
            switch (target) {
                .surface => |surface| {
                    const rt_surface = surface.rt_surface;
                    _ = win32.InvalidateRect(rt_surface.hwnd, null, 0);
                },
                .app => {},
            }
            return true;
        },

        .quit => {
            self.closeAllWindows();
            self.running = false;
            return true;
        },

        .close_all_windows => {
            self.closeAllWindows();
            self.running = false;
            return true;
        },

        .ring_bell => {
            _ = win32.MessageBeep(0);
            return true;
        },

        .new_split => {
            // For now, open a new window as a split fallback
            try self.newWindow();
            return true;
        },

        .new_tab => {
            // For now, open a new window as a tab fallback
            try self.newWindow();
            return true;
        },

        .mouse_shape => return false,
        .mouse_visibility => return false,
        .cell_size => return false,
        .size_limit => return false,
        .initial_size => return false,
        .quit_timer => return false,
        .config_change => return false,

        else => return false,
    }
}

pub fn performIpc(
    _: Allocator,
    _: apprt.ipc.Target,
    comptime action: apprt.ipc.Action.Key,
    _: apprt.ipc.Action.Value(action),
) !bool {
    return false;
}

pub fn redrawInspector(_: *App, _: *Surface) void {}

/// Create a new terminal window.
fn newWindow(self: *App) !void {
    const surface = try self.alloc.create(Surface);
    errdefer self.alloc.destroy(surface);

    try surface.init(self);
    errdefer surface.deinit();

    try self.surfaces.append(self.alloc, surface);
}

/// Remove a surface from the list (called when window is destroyed).
pub fn removeSurface(self: *App, surface: *Surface) void {
    var i: usize = 0;
    while (i < self.surfaces.items.len) {
        if (self.surfaces.items[i] == surface) {
            _ = self.surfaces.swapRemove(i);
            continue;
        }
        i += 1;
    }
}

fn closeAllWindows(self: *App) void {
    while (self.surfaces.items.len > 0) {
        const surface = self.surfaces.items[self.surfaces.items.len - 1];
        surface.close(false);
    }
}
