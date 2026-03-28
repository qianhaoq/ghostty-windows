/// Win32 surface (window) for Ghostty on Windows.
/// Each surface represents a single terminal window with its own OpenGL context.
const Self = @This();

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const apprt = @import("../../apprt.zig");
const configpkg = @import("../../config.zig");
const CoreSurface = @import("../../Surface.zig");
const CoreApp = @import("../../App.zig");
const input = @import("../../input.zig");
const internal_os = @import("../../os/main.zig");

const App = @import("App.zig");
const win32 = @import("win32.zig");
const wgl = @import("wgl.zig");
const key_mod = @import("key.zig");

const log = std.log.scoped(.win32_surface);

/// The Win32 window handle.
hwnd: win32.HWND = undefined,

/// The WGL OpenGL context.
gl_context: ?wgl.Context = null,

/// The core surface pointer (initialized after window is created and sized).
core_surface_ptr: ?*CoreSurface = null,

/// The parent app.
app: *App,

/// Current window size in pixels.
width: u32 = 800,
height: u32 = 600,

/// Current DPI.
dpi: u32 = win32.USER_DEFAULT_SCREEN_DPI,

/// Title storage.
title: ?[:0]const u8 = null,

/// Initialize the surface by creating a Win32 window.
pub fn init(self: *Self, app: *App) !void {
    self.* = .{
        .app = app,
    };

    const hwnd = win32.CreateWindowExW(
        win32.WS_EX_APPWINDOW,
        @import("App.zig").class_name,
        std.unicode.utf8ToUtf16LeStringLiteral("Ghostty"),
        win32.WS_OVERLAPPEDWINDOW | win32.WS_CLIPCHILDREN | win32.WS_CLIPSIBLINGS,
        win32.CW_USEDEFAULT,
        win32.CW_USEDEFAULT,
        1024,
        768,
        null,
        null,
        app.hinstance,
        @ptrCast(self), // Pass self as create param
    ) orelse return error.CreateWindowFailed;

    self.hwnd = hwnd;

    // Store self pointer in window user data for WndProc
    _ = win32.SetWindowLongPtrW(hwnd, win32.GWLP_USERDATA, @bitCast(@intFromPtr(self)));

    // Get DPI for this window
    self.dpi = win32.GetDpiForWindow(hwnd);
    if (self.dpi == 0) self.dpi = win32.USER_DEFAULT_SCREEN_DPI;

    // Initialize OpenGL context
    self.gl_context = wgl.Context.init(hwnd) catch |err| {
        log.err("failed to create OpenGL context: {}", .{err});
        return error.OpenGLInitFailed;
    };

    // Get initial window size
    var rect: win32.RECT = undefined;
    if (win32.GetClientRect(hwnd, &rect) != 0) {
        self.width = @intCast(rect.right - rect.left);
        self.height = @intCast(rect.bottom - rect.top);
    }

    // Initialize the core surface
    try self.initCoreSurface();

    // Show the window
    _ = win32.ShowWindow(hwnd, win32.SW_SHOWDEFAULT);
    _ = win32.UpdateWindow(hwnd);

    log.info("Win32 surface created: {}x{} @ {}dpi", .{ self.width, self.height, self.dpi });
}

/// Initialize the core surface (terminal + renderer + IO).
fn initCoreSurface(self: *Self) !void {
    const core_app = self.app.core_app;
    const alloc = self.app.alloc;

    // Load config
    var config = try configpkg.Config.load(alloc);
    defer config.deinit();

    // Allocate the core surface
    const surface = try alloc.create(CoreSurface);
    errdefer alloc.destroy(surface);

    // Register with core app
    try core_app.addSurface(self.asApprtSurface());
    errdefer core_app.deleteSurface(self.asApprtSurface());

    // Initialize the core surface
    try surface.init(
        alloc,
        &config,
        core_app,
        self.app,
        self.asApprtSurface(),
    );

    self.core_surface_ptr = surface;
}

/// Get a pointer to self as an apprt.Surface.
fn asApprtSurface(self: *Self) *apprt.Surface {
    return @ptrCast(self);
}

pub fn deinit(self: *Self) void {
    // Deinit core surface (stops renderer and IO threads)
    if (self.core_surface_ptr) |cs| {
        cs.deinit();
        self.app.alloc.destroy(cs);
        self.core_surface_ptr = null;
    }

    // Remove from core app
    self.app.core_app.deleteSurface(self.asApprtSurface());

    if (self.title) |title| {
        self.app.alloc.free(title);
        self.title = null;
    }

    // Destroy OpenGL context
    if (self.gl_context) |*ctx| {
        ctx.deinit(self.hwnd);
        self.gl_context = null;
    }

    // Destroy window
    _ = win32.DestroyWindow(self.hwnd);
}

pub fn core(self: *Self) *CoreSurface {
    return self.core_surface_ptr.?;
}

pub fn rtApp(self: *Self) *App {
    return self.app;
}

pub fn close(self: *Self, process_active: bool) void {
    _ = process_active;
    // Remove from app's surface list
    self.app.removeSurface(self);
    self.deinit();
    self.app.alloc.destroy(self);
}

pub fn getTitle(self: *Self) ?[:0]const u8 {
    return self.title;
}

pub fn getContentScale(self: *const Self) !apprt.ContentScale {
    const scale: f32 = @as(f32, @floatFromInt(self.dpi)) / @as(f32, @floatFromInt(win32.USER_DEFAULT_SCREEN_DPI));
    return .{ .x = scale, .y = scale };
}

pub fn getSize(self: *const Self) !apprt.SurfaceSize {
    return .{ .width = self.width, .height = self.height };
}

pub fn getCursorPos(self: *const Self) !apprt.CursorPos {
    var point: win32.POINT = undefined;
    if (win32.GetCursorPos(&point) != 0) {
        _ = win32.ScreenToClient(self.hwnd, &point);
        return .{
            .x = @floatFromInt(point.x),
            .y = @floatFromInt(point.y),
        };
    }
    return .{ .x = 0, .y = 0 };
}

pub fn supportsClipboard(
    _: *const Self,
    clipboard_type: apprt.Clipboard,
) bool {
    return switch (clipboard_type) {
        .standard => true,
        .selection, .primary => false,
    };
}

pub fn clipboardRequest(
    self: *Self,
    clipboard_type: apprt.Clipboard,
    state: apprt.ClipboardRequest,
) !bool {
    _ = clipboard_type;

    // Read from Win32 clipboard
    if (win32.OpenClipboard(self.hwnd) == 0) return false;
    defer _ = win32.CloseClipboard();

    const handle = win32.GetClipboardData(win32.CF_UNICODETEXT) orelse return false;
    const ptr = win32.GlobalLock(handle) orelse return false;
    defer _ = win32.GlobalUnlock(handle);

    // Convert UTF-16 to UTF-8
    const wide: [*:0]const u16 = @ptrCast(@alignCast(ptr));
    var len: usize = 0;
    while (wide[len] != 0) len += 1;
    const utf8 = std.unicode.utf16LeToUtf8Alloc(self.app.alloc, wide[0..len]) catch return false;
    defer self.app.alloc.free(utf8);

    // Create null-terminated copy
    const utf8z = self.app.alloc.dupeZ(u8, utf8) catch return false;
    defer self.app.alloc.free(utf8z);

    // Complete the clipboard request
    const cs = self.core_surface_ptr orelse return false;
    cs.completeClipboardRequest(state, utf8z, true) catch return false;
    return true;
}

pub fn setClipboard(
    self: *Self,
    clipboard_type: apprt.Clipboard,
    contents: []const apprt.ClipboardContent,
    confirm: bool,
) !void {
    _ = clipboard_type;
    _ = confirm;

    // Find text content
    var text: ?[]const u8 = null;
    for (contents) |content| {
        if (std.mem.eql(u8, content.mime, "text/plain") or
            std.mem.startsWith(u8, content.mime, "text/"))
        {
            text = content.data;
            break;
        }
    }

    const data = text orelse return;

    // Convert UTF-8 to UTF-16
    const wide = std.unicode.utf8ToUtf16LeAlloc(self.app.alloc, data) catch return;
    defer self.app.alloc.free(wide);

    // Allocate global memory for clipboard
    const size = (wide.len + 1) * @sizeOf(u16);
    const hmem = win32.GlobalAlloc(win32.GMEM_MOVEABLE, size) orelse return;
    const dest = win32.GlobalLock(hmem) orelse return;

    // Copy UTF-16 data
    const dest_wide: [*]u16 = @ptrCast(@alignCast(dest));
    @memcpy(dest_wide[0..wide.len], wide);
    dest_wide[wide.len] = 0; // null terminator
    _ = win32.GlobalUnlock(hmem);

    // Set clipboard
    if (win32.OpenClipboard(self.hwnd) == 0) return;
    defer _ = win32.CloseClipboard();
    _ = win32.EmptyClipboard();
    _ = win32.SetClipboardData(win32.CF_UNICODETEXT, hmem);
}

pub fn defaultTermioEnv(self: *Self) !std.process.EnvMap {
    var env = try internal_os.getEnvMap(self.app.alloc);
    errdefer env.deinit();
    try env.put("TERM", "xterm-256color");
    try env.put("COLORTERM", "truecolor");
    return env;
}

// -------- Win32 Window Procedure --------

pub fn wndProc(hwnd: win32.HWND, msg: win32.UINT, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(.c) win32.LRESULT {
    // Retrieve the surface pointer from window user data
    const self = getSelf(hwnd) orelse
        return win32.DefWindowProcW(hwnd, msg, wParam, lParam);

    switch (msg) {
        win32.WM_SIZE => {
            const w: u16 = @bitCast(win32.loword(lParam));
            const h: u16 = @bitCast(win32.hiword(lParam));
            const width: u32 = @intCast(w);
            const height: u32 = @intCast(h);
            if (width > 0 and height > 0) {
                self.width = width;
                self.height = height;
                if (self.core_surface_ptr) |cs| {
                    cs.sizeCallback(.{ .width = self.width, .height = self.height }) catch {};
                }
            }
            return 0;
        },

        win32.WM_SETFOCUS => {
            if (self.core_surface_ptr) |cs| {
                cs.focusCallback(true) catch {};
            }
            return 0;
        },

        win32.WM_KILLFOCUS => {
            if (self.core_surface_ptr) |cs| {
                cs.focusCallback(false) catch {};
            }
            return 0;
        },

        win32.WM_KEYDOWN, win32.WM_SYSKEYDOWN => {
            self.handleKeyEvent(.press, wParam, lParam);
            return 0;
        },

        win32.WM_KEYUP, win32.WM_SYSKEYUP => {
            self.handleKeyEvent(.release, wParam, lParam);
            return 0;
        },

        win32.WM_CHAR => {
            // We handle text input in WM_KEYDOWN via ToUnicodeEx
            return 0;
        },

        win32.WM_MOUSEMOVE => {
            if (self.core_surface_ptr) |cs| {
                cs.cursorPosCallback(.{
                    .x = win32.getXLparam(lParam),
                    .y = win32.getYLparam(lParam),
                }, null) catch {};
            }
            return 0;
        },

        win32.WM_LBUTTONDOWN => {
            self.handleMouseButton(.left, .press, lParam);
            return 0;
        },

        win32.WM_LBUTTONUP => {
            self.handleMouseButton(.left, .release, lParam);
            return 0;
        },

        win32.WM_RBUTTONDOWN => {
            self.handleMouseButton(.right, .press, lParam);
            return 0;
        },

        win32.WM_RBUTTONUP => {
            self.handleMouseButton(.right, .release, lParam);
            return 0;
        },

        win32.WM_MBUTTONDOWN => {
            self.handleMouseButton(.middle, .press, lParam);
            return 0;
        },

        win32.WM_MBUTTONUP => {
            self.handleMouseButton(.middle, .release, lParam);
            return 0;
        },

        win32.WM_MOUSEWHEEL => {
            if (self.core_surface_ptr) |cs| {
                const delta = win32.hiwordW(wParam);
                const scroll_y: f64 = @as(f64, @floatFromInt(delta)) / 120.0;
                cs.scrollCallback(0, scroll_y, .{}) catch {};
            }
            return 0;
        },

        win32.WM_PAINT => {
            // Validate the region to prevent continuous WM_PAINT
            _ = win32.ValidateRect(hwnd, null);
            return 0;
        },

        win32.WM_ERASEBKGND => {
            // Return 1 to indicate we handle background erasing (prevents flicker)
            return 1;
        },

        win32.WM_CLOSE => {
            if (self.core_surface_ptr) |cs| {
                cs.close();
            } else {
                self.close(false);
            }
            return 0;
        },

        win32.WM_DESTROY => {
            // If no more surfaces, quit
            if (self.app.surfaces.items.len == 0) {
                win32.PostQuitMessage(0);
            }
            return 0;
        },

        win32.WM_DPICHANGED => {
            const new_dpi: u32 = @intCast(win32.lowordW(wParam));
            self.dpi = new_dpi;
            if (self.core_surface_ptr) |cs| {
                const scale = try self.getContentScale();
                cs.contentScaleCallback(scale) catch {};
            }
            return 0;
        },

        win32.WM_APP_WAKEUP => {
            // Wakeup message from other threads - processed in main loop via tick()
            return 0;
        },

        else => {},
    }

    return win32.DefWindowProcW(hwnd, msg, wParam, lParam);
}

/// Get the Surface pointer from HWND user data.
fn getSelf(hwnd: win32.HWND) ?*Self {
    const ptr = win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA);
    if (ptr == 0) return null;
    return @ptrFromInt(@as(usize, @bitCast(ptr)));
}

/// Handle a keyboard event.
fn handleKeyEvent(self: *Self, action: input.Action, wParam: win32.WPARAM, lParam: win32.LPARAM) void {
    const cs = self.core_surface_ptr orelse return;

    const vk: c_uint = @intCast(wParam);
    const scan_code: c_uint = @intCast((lParam >> 16) & 0xFF);
    const physical_key = key_mod.vkToKey(vk);
    const mods = key_mod.getModifiers();

    // Get text for the key
    var text_buf: [16]u8 = undefined;
    const text_len = if (action == .press)
        key_mod.getKeyText(vk, scan_code, &text_buf)
    else
        0;
    const text: ?[]const u8 = if (text_len > 0) text_buf[0..text_len] else null;

    const event = input.KeyEvent{
        .action = action,
        .key = physical_key,
        .mods = mods,
        .consumed_mods = .{},
        .composing = false,
        .utf8 = if (text) |t| t else "",
        .unshifted_codepoint = key_mod.getUnshiftedCodepoint(vk) orelse if (text) |t|
            std.unicode.utf8Decode(t) catch 0
        else
            0,
    };

    _ = cs.keyCallback(event) catch {};
}

/// Handle a mouse button event.
fn handleMouseButton(self: *Self, button: input.MouseButton, action: input.MouseButtonState, lParam: win32.LPARAM) void {
    const cs = self.core_surface_ptr orelse return;
    const mods = key_mod.getModifiers();

    cs.cursorPosCallback(.{
        .x = win32.getXLparam(lParam),
        .y = win32.getYLparam(lParam),
    }, mods) catch {};

    _ = cs.mouseButtonCallback(action, button, mods) catch {};
}
