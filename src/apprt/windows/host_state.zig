const std = @import("std");
const win32 = @import("win32.zig");

pub const ProgressState = enum {
    remove,
    set,
    @"error",
    indeterminate,
    pause,
};

pub const Progress = struct {
    state: ProgressState = .remove,
    percent: ?u8 = null,
};

pub const Search = struct {
    active: bool = false,
    total: ?usize = null,
    selected: ?usize = null,
};

pub const TitleOptions = struct {
    base_title: []const u8,
    readonly: bool = false,
    progress: ?Progress = null,
    search: Search = .{},
};

pub fn windowStyle() win32.DWORD {
    return win32.WS_OVERLAPPEDWINDOW | win32.WS_CLIPCHILDREN | win32.WS_CLIPSIBLINGS;
}

pub fn borderlessWindowStyle() win32.DWORD {
    return win32.WS_POPUP | win32.WS_CLIPCHILDREN | win32.WS_CLIPSIBLINGS;
}

pub fn frameStyle(decorated: bool, fullscreen: bool) win32.DWORD {
    if (fullscreen or !decorated) return borderlessWindowStyle();
    return windowStyle();
}

pub fn imeExcludeRect(x: f64, y: f64, width: f64, height: f64) win32.RECT {
    const left: win32.LONG = @intFromFloat(x);
    const bottom: win32.LONG = @intFromFloat(y);
    const rect_width: win32.LONG = @intFromFloat(@max(width, 1.0));
    const rect_height: win32.LONG = @intFromFloat(@max(height, 1.0));

    return .{
        .left = left,
        .top = bottom - rect_height,
        .right = left + rect_width,
        .bottom = bottom,
    };
}

pub fn effectiveTitle(
    terminal_title: ?[]const u8,
    surface_title_override: ?[]const u8,
    tab_title_override: ?[]const u8,
) []const u8 {
    if (surface_title_override) |title| {
        if (title.len > 0) return title;
    }

    if (tab_title_override) |title| {
        if (title.len > 0) return title;
    }

    if (terminal_title) |title| {
        if (title.len > 0) return title;
    }

    return "Ghostty";
}

pub fn formatWindowTitle(alloc: std.mem.Allocator, opts: TitleOptions) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(alloc);
    const writer = list.writer(alloc);

    if (opts.readonly) try writer.writeAll("[Read-Only] ");

    if (opts.progress) |progress| {
        switch (progress.state) {
            .remove => {},
            .set => if (progress.percent) |percent|
                try writer.print("[{d}%] ", .{percent})
            else
                try writer.writeAll("[Working] "),
            .@"error" => try writer.writeAll("[Error] "),
            .indeterminate => try writer.writeAll("[Working] "),
            .pause => try writer.writeAll("[Paused] "),
        }
    }

    if (opts.search.active) {
        if (opts.search.selected) |selected| {
            if (opts.search.total) |total| {
                try writer.print("[Search {d}/{d}] ", .{ selected, total });
            } else {
                try writer.print("[Search {d}] ", .{selected});
            }
        } else if (opts.search.total) |total| {
            try writer.print("[Search {d}] ", .{total});
        } else {
            try writer.writeAll("[Search] ");
        }
    }

    try writer.writeAll(if (opts.base_title.len > 0) opts.base_title else "Ghostty");
    return list.toOwnedSlice(alloc);
}

test "frame style keeps decorated windows overlapped" {
    try std.testing.expectEqual(windowStyle(), frameStyle(true, false));
}

test "frame style uses borderless for undecorated windows" {
    try std.testing.expectEqual(borderlessWindowStyle(), frameStyle(false, false));
}

test "frame style uses borderless for fullscreen windows" {
    try std.testing.expectEqual(borderlessWindowStyle(), frameStyle(true, true));
}

test "ime exclude rect clamps to at least one pixel" {
    const rect = imeExcludeRect(12.9, 24.1, 0, 0);
    try std.testing.expectEqual(@as(win32.LONG, 12), rect.left);
    try std.testing.expectEqual(@as(win32.LONG, 23), rect.top);
    try std.testing.expectEqual(@as(win32.LONG, 13), rect.right);
    try std.testing.expectEqual(@as(win32.LONG, 24), rect.bottom);
}

test "ime exclude rect expands using width and height" {
    const rect = imeExcludeRect(40, 60, 18, 12);
    try std.testing.expectEqual(@as(win32.LONG, 40), rect.left);
    try std.testing.expectEqual(@as(win32.LONG, 48), rect.top);
    try std.testing.expectEqual(@as(win32.LONG, 58), rect.right);
    try std.testing.expectEqual(@as(win32.LONG, 60), rect.bottom);
}

test "effective title prefers surface override over tab and terminal" {
    try std.testing.expectEqualStrings(
        "surface",
        effectiveTitle("terminal", "surface", "tab"),
    );
}

test "effective title falls back through tab then terminal" {
    try std.testing.expectEqualStrings(
        "tab",
        effectiveTitle("terminal", null, "tab"),
    );
    try std.testing.expectEqualStrings(
        "terminal",
        effectiveTitle("terminal", null, null),
    );
}

test "effective title falls back to default when empty" {
    try std.testing.expectEqualStrings(
        "Ghostty",
        effectiveTitle("", "", ""),
    );
}

test "window title formatting includes readonly progress and search state" {
    const title = try formatWindowTitle(std.testing.allocator, .{
        .base_title = "shell",
        .readonly = true,
        .progress = .{ .state = .set, .percent = 42 },
        .search = .{ .active = true, .total = 10, .selected = 3 },
    });
    defer std.testing.allocator.free(title);

    try std.testing.expectEqualStrings(
        "[Read-Only] [42%] [Search 3/10] shell",
        title,
    );
}

test "window title formatting falls back to default title" {
    const title = try formatWindowTitle(std.testing.allocator, .{
        .base_title = "",
        .progress = .{ .state = .indeterminate },
    });
    defer std.testing.allocator.free(title);

    try std.testing.expectEqualStrings("[Working] Ghostty", title);
}
