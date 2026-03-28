/// Windows Virtual Key code to Ghostty input.Key mapping.
const key = @This();

const std = @import("std");
const input = @import("../../input.zig");
const win32 = @import("win32.zig");

/// Convert a Windows Virtual Key code to a Ghostty input.Key.
pub fn vkToKey(vk: c_uint) input.Key {
    return switch (vk) {
        win32.VK_BACK => .backspace,
        win32.VK_TAB => .tab,
        win32.VK_RETURN => .enter,
        win32.VK_PAUSE => .pause,
        win32.VK_CAPITAL => .caps_lock,
        win32.VK_ESCAPE => .escape,
        win32.VK_SPACE => .space,
        win32.VK_PRIOR => .page_up,
        win32.VK_NEXT => .page_down,
        win32.VK_END => .end,
        win32.VK_HOME => .home,
        win32.VK_LEFT => .arrow_left,
        win32.VK_UP => .arrow_up,
        win32.VK_RIGHT => .arrow_right,
        win32.VK_DOWN => .arrow_down,
        win32.VK_INSERT => .insert,
        win32.VK_DELETE => .delete,

        // Number keys 0-9
        0x30 => .digit_0,
        0x31 => .digit_1,
        0x32 => .digit_2,
        0x33 => .digit_3,
        0x34 => .digit_4,
        0x35 => .digit_5,
        0x36 => .digit_6,
        0x37 => .digit_7,
        0x38 => .digit_8,
        0x39 => .digit_9,

        // Letter keys A-Z
        0x41 => .key_a,
        0x42 => .key_b,
        0x43 => .key_c,
        0x44 => .key_d,
        0x45 => .key_e,
        0x46 => .key_f,
        0x47 => .key_g,
        0x48 => .key_h,
        0x49 => .key_i,
        0x4A => .key_j,
        0x4B => .key_k,
        0x4C => .key_l,
        0x4D => .key_m,
        0x4E => .key_n,
        0x4F => .key_o,
        0x50 => .key_p,
        0x51 => .key_q,
        0x52 => .key_r,
        0x53 => .key_s,
        0x54 => .key_t,
        0x55 => .key_u,
        0x56 => .key_v,
        0x57 => .key_w,
        0x58 => .key_x,
        0x59 => .key_y,
        0x5A => .key_z,

        // Function keys
        win32.VK_F1 => .f1,
        win32.VK_F2 => .f2,
        win32.VK_F3 => .f3,
        win32.VK_F4 => .f4,
        win32.VK_F5 => .f5,
        win32.VK_F6 => .f6,
        win32.VK_F7 => .f7,
        win32.VK_F8 => .f8,
        win32.VK_F9 => .f9,
        win32.VK_F10 => .f10,
        win32.VK_F11 => .f11,
        win32.VK_F12 => .f12,

        // Modifier keys
        win32.VK_SHIFT => .shift_left,
        win32.VK_CONTROL => .control_left,
        win32.VK_MENU => .alt_left,
        win32.VK_LSHIFT => .shift_left,
        win32.VK_RSHIFT => .shift_right,
        win32.VK_LCONTROL => .control_left,
        win32.VK_RCONTROL => .control_right,
        win32.VK_LMENU => .alt_left,
        win32.VK_RMENU => .alt_right,
        win32.VK_LWIN => .meta_left,
        win32.VK_RWIN => .meta_right,
        win32.VK_NUMLOCK => .num_lock,
        win32.VK_SCROLL => .scroll_lock,

        // OEM keys
        win32.VK_OEM_1 => .semicolon,
        win32.VK_OEM_PLUS => .equal,
        win32.VK_OEM_COMMA => .comma,
        win32.VK_OEM_MINUS => .minus,
        win32.VK_OEM_PERIOD => .period,
        win32.VK_OEM_2 => .slash,
        win32.VK_OEM_3 => .backquote,
        win32.VK_OEM_4 => .bracket_left,
        win32.VK_OEM_5 => .backslash,
        win32.VK_OEM_6 => .bracket_right,
        win32.VK_OEM_7 => .quote,

        else => .unidentified,
    };
}

/// Get the current keyboard modifier state.
pub fn getModifiers() input.Mods {
    var mods: input.Mods = .{};
    if (win32.GetKeyState(win32.VK_SHIFT) < 0) mods.shift = true;
    if (win32.GetKeyState(win32.VK_CONTROL) < 0) mods.ctrl = true;
    if (win32.GetKeyState(win32.VK_MENU) < 0) mods.alt = true;
    if (win32.GetKeyState(win32.VK_LWIN) < 0 or win32.GetKeyState(win32.VK_RWIN) < 0) mods.super = true;
    if (win32.GetKeyState(win32.VK_CAPITAL) & 1 != 0) mods.caps_lock = true;
    if (win32.GetKeyState(win32.VK_NUMLOCK) & 1 != 0) mods.num_lock = true;
    return mods;
}

/// Get the UTF-8 text for a key event using ToUnicodeEx.
/// Returns the number of bytes written, or 0 if no text was generated.
pub fn getKeyText(vk: c_uint, scan_code: c_uint, buf: []u8) usize {
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

    const utf16_len: usize = @intCast(result);
    const utf8_len = std.unicode.utf16LeToUtf8(buf, utf16_buf[0..utf16_len]) catch return 0;
    return utf8_len;
}

/// Get the unshifted codepoint for a key event.
///
/// This is used for layout-aware keybindings such as ctrl+shift+c where the
/// active modifier state may prevent ToUnicodeEx from returning the base
/// character we need to match.
pub fn getUnshiftedCodepoint(vk: c_uint) ?u21 {
    return switch (vk) {
        win32.VK_BACK => 0x08,
        win32.VK_TAB => 0x09,
        win32.VK_RETURN => 0x0D,
        win32.VK_SPACE => ' ',
        else => mapped: {
            const mapped = win32.MapVirtualKeyW(vk, win32.MAPVK_VK_TO_CHAR);
            if (mapped == 0) break :mapped null;

            // MAPVK_VK_TO_CHAR returns the translated character in the low
            // word and sets the high bit if the key is a dead key.
            const codepoint = mapped & 0x7FFF;
            if (codepoint == 0) break :mapped null;

            const normalized = if (codepoint >= 'A' and codepoint <= 'Z')
                codepoint + ('a' - 'A')
            else
                codepoint;

            break :mapped std.math.cast(u21, normalized);
        },
    };
}
