/// Win32 API declarations for user32.dll, gdi32.dll, and opengl32.dll.
/// Only includes the functions needed by the Ghostty Windows apprt.
const std = @import("std");
const windows = std.os.windows;

pub const HWND = windows.HWND;
pub const HDC = *opaque {};
pub const HGLRC = *opaque {};
pub const HINSTANCE = windows.HINSTANCE;
pub const HMODULE = windows.HMODULE;
pub const HICON = *opaque {};
pub const HCURSOR = *opaque {};
pub const HBRUSH = *opaque {};
pub const HMENU = *opaque {};
pub const HMONITOR = *opaque {};
pub const HIMC = *opaque {};
pub const ATOM = u16;
pub const BOOL = windows.BOOL;
pub const UINT = c_uint;
pub const WPARAM = windows.WPARAM;
pub const LPARAM = windows.LPARAM;
pub const LRESULT = windows.LRESULT;
pub const LONG = c_long;
pub const DWORD = windows.DWORD;
pub const BYTE = u8;
pub const WORD = u16;
pub const LPCWSTR = [*:0]const u16;
pub const LPVOID = ?*anyopaque;

pub const RECT = extern struct {
    left: LONG,
    top: LONG,
    right: LONG,
    bottom: LONG,
};

pub const POINT = extern struct {
    x: LONG,
    y: LONG,
};

pub const MSG = extern struct {
    hwnd: ?HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: DWORD,
    pt: POINT,
};

pub const WNDCLASSEXW = extern struct {
    cbSize: UINT = @sizeOf(WNDCLASSEXW),
    style: UINT = 0,
    lpfnWndProc: WNDPROC,
    cbClsExtra: c_int = 0,
    cbWndExtra: c_int = 0,
    hInstance: ?HINSTANCE = null,
    hIcon: ?HICON = null,
    hCursor: ?HCURSOR = null,
    hbrBackground: ?HBRUSH = null,
    lpszMenuName: ?LPCWSTR = null,
    lpszClassName: LPCWSTR,
    hIconSm: ?HICON = null,
};

pub const PIXELFORMATDESCRIPTOR = extern struct {
    nSize: WORD = @sizeOf(PIXELFORMATDESCRIPTOR),
    nVersion: WORD = 1,
    dwFlags: DWORD = 0,
    iPixelType: BYTE = 0,
    cColorBits: BYTE = 0,
    cRedBits: BYTE = 0,
    cRedShift: BYTE = 0,
    cGreenBits: BYTE = 0,
    cGreenShift: BYTE = 0,
    cBlueBits: BYTE = 0,
    cBlueShift: BYTE = 0,
    cAlphaBits: BYTE = 0,
    cAlphaShift: BYTE = 0,
    cAccumBits: BYTE = 0,
    cAccumRedBits: BYTE = 0,
    cAccumGreenBits: BYTE = 0,
    cAccumBlueBits: BYTE = 0,
    cAccumAlphaBits: BYTE = 0,
    cDepthBits: BYTE = 0,
    cStencilBits: BYTE = 0,
    cAuxBuffers: BYTE = 0,
    iLayerType: BYTE = 0,
    bReserved: BYTE = 0,
    dwLayerMask: DWORD = 0,
    dwVisibleMask: DWORD = 0,
    dwDamageMask: DWORD = 0,
};

pub const WNDPROC = *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.c) LRESULT;

pub const CREATESTRUCTW = extern struct {
    lpCreateParams: ?*anyopaque,
    hInstance: ?HINSTANCE,
    hMenu: ?HMENU,
    hwndParent: ?HWND,
    cy: c_int,
    cx: c_int,
    y: c_int,
    x: c_int,
    style: LONG,
    lpszName: ?LPCWSTR,
    lpszClass: ?LPCWSTR,
    dwExStyle: DWORD,
};

pub const MINMAXINFO = extern struct {
    ptReserved: POINT,
    ptMaxSize: POINT,
    ptMaxPosition: POINT,
    ptMinTrackSize: POINT,
    ptMaxTrackSize: POINT,
};

pub const MONITORINFO = extern struct {
    cbSize: DWORD = @sizeOf(MONITORINFO),
    rcMonitor: RECT,
    rcWork: RECT,
    dwFlags: DWORD = 0,
};

pub const COMPOSITIONFORM = extern struct {
    dwStyle: DWORD,
    ptCurrentPos: POINT,
    rcArea: RECT,
};

pub const CANDIDATEFORM = extern struct {
    dwIndex: DWORD,
    dwStyle: DWORD,
    ptCurrentPos: POINT,
    rcArea: RECT,
};

pub const FLASHWINFO = extern struct {
    cbSize: UINT = @sizeOf(FLASHWINFO),
    hwnd: HWND,
    dwFlags: DWORD,
    uCount: UINT,
    dwTimeout: DWORD,
};

// Window styles
pub const WS_POPUP = 0x80000000;
pub const WS_OVERLAPPEDWINDOW = 0x00CF0000;
pub const WS_VISIBLE = 0x10000000;
pub const WS_CLIPCHILDREN = 0x02000000;
pub const WS_CLIPSIBLINGS = 0x04000000;

// Extended window styles
pub const WS_EX_APPWINDOW = 0x00040000;

// Window messages
pub const WM_CREATE = 0x0001;
pub const WM_DESTROY = 0x0002;
pub const WM_SIZE = 0x0005;
pub const WM_SETFOCUS = 0x0007;
pub const WM_KILLFOCUS = 0x0008;
pub const WM_CLOSE = 0x0010;
pub const WM_QUIT = 0x0012;
pub const WM_PAINT = 0x000F;
pub const WM_ERASEBKGND = 0x0014;
pub const WM_SETCURSOR = 0x0020;
pub const WM_GETMINMAXINFO = 0x0024;
pub const WM_NCCREATE = 0x0081;
pub const WM_KEYDOWN = 0x0100;
pub const WM_KEYUP = 0x0101;
pub const WM_CHAR = 0x0102;
pub const WM_IME_STARTCOMPOSITION = 0x010D;
pub const WM_IME_ENDCOMPOSITION = 0x010E;
pub const WM_IME_COMPOSITION = 0x010F;
pub const WM_SYSKEYDOWN = 0x0104;
pub const WM_SYSKEYUP = 0x0105;
pub const WM_MOUSEMOVE = 0x0200;
pub const WM_LBUTTONDOWN = 0x0201;
pub const WM_LBUTTONUP = 0x0202;
pub const WM_RBUTTONDOWN = 0x0204;
pub const WM_RBUTTONUP = 0x0205;
pub const WM_MBUTTONDOWN = 0x0207;
pub const WM_MBUTTONUP = 0x0208;
pub const WM_MOUSEWHEEL = 0x020A;
pub const WM_MOUSEHWHEEL = 0x020E;
pub const WM_DPICHANGED = 0x02E0;
pub const WM_APP = 0x8000;

// Custom messages
pub const WM_APP_WAKEUP = WM_APP + 1;

// ShowWindow commands
pub const SW_HIDE = 0;
pub const SW_MAXIMIZE = 3;
pub const SW_SHOW = 5;
pub const SW_RESTORE = 9;
pub const SW_SHOWDEFAULT = 10;

// CW_USEDEFAULT
pub const CW_USEDEFAULT: c_int = @bitCast(@as(c_uint, 0x80000000));

// Pixel format flags
pub const PFD_DRAW_TO_WINDOW = 0x00000004;
pub const PFD_SUPPORT_OPENGL = 0x00000020;
pub const PFD_DOUBLEBUFFER = 0x00000001;
pub const PFD_TYPE_RGBA: BYTE = 0;
pub const PFD_MAIN_PLANE: BYTE = 0;

// Cursor resource IDs
pub const IDC_ARROW_ID: usize = 32512;
pub const IDC_IBEAM_ID: usize = 32513;
pub const IDC_WAIT_ID: usize = 32514;
pub const IDC_SIZEWE_ID: usize = 32644;
pub const IDC_SIZENS_ID: usize = 32645;
pub const IDC_SIZEALL_ID: usize = 32646;
pub const IDC_NO_ID: usize = 32648;
pub const IDC_HAND_ID: usize = 32649;

/// Load a system cursor by resource ID (MAKEINTRESOURCE-style).
/// Windows MAKEINTRESOURCE casts a small integer to LPCWSTR.
/// We declare a separate extern with usize param to avoid alignment issues.
pub fn loadSystemCursor(id: usize) ?HCURSOR {
    // Use the _byId variant which takes usize directly
    return loadCursorById(null, id);
}

/// LoadCursorW with usize second parameter to handle MAKEINTRESOURCE.
/// The Windows ABI treats the second param as a pointer OR integer.
const loadCursorById = @extern(*const fn (?HINSTANCE, usize) callconv(.c) ?HCURSOR, .{
    .name = "LoadCursorW",
    .library_name = "user32",
});

// Color
pub const COLOR_WINDOW = 5;

// Hit test
pub const HTCLIENT: u16 = 1;

// IMM composition results
pub const GCS_COMPSTR: DWORD = 0x0008;
pub const GCS_RESULTSTR: DWORD = 0x0800;

// IME window placement
pub const CFS_POINT: DWORD = 0x0002;
pub const CFS_CANDIDATEPOS: DWORD = 0x0040;
pub const CFS_EXCLUDE: DWORD = 0x0080;

// WGL context attribute keys
pub const WGL_CONTEXT_MAJOR_VERSION_ARB = 0x2091;
pub const WGL_CONTEXT_MINOR_VERSION_ARB = 0x2092;
pub const WGL_CONTEXT_PROFILE_MASK_ARB = 0x9126;
pub const WGL_CONTEXT_CORE_PROFILE_BIT_ARB = 0x00000001;
pub const WGL_CONTEXT_FLAGS_ARB = 0x2094;
pub const WGL_CONTEXT_DEBUG_BIT_ARB = 0x0001;

// WGL pixel format attribute keys
pub const WGL_DRAW_TO_WINDOW_ARB = 0x2001;
pub const WGL_SUPPORT_OPENGL_ARB = 0x2010;
pub const WGL_DOUBLE_BUFFER_ARB = 0x2011;
pub const WGL_PIXEL_TYPE_ARB = 0x2013;
pub const WGL_TYPE_RGBA_ARB = 0x202B;
pub const WGL_COLOR_BITS_ARB = 0x2014;
pub const WGL_DEPTH_BITS_ARB = 0x2022;
pub const WGL_STENCIL_BITS_ARB = 0x2023;
pub const WGL_ACCELERATION_ARB = 0x2003;
pub const WGL_FULL_ACCELERATION_ARB = 0x2027;
pub const WGL_SAMPLE_BUFFERS_ARB = 0x2041;
pub const WGL_SAMPLES_ARB = 0x2042;

// Virtual Key codes
pub const VK_BACK = 0x08;
pub const VK_TAB = 0x09;
pub const VK_RETURN = 0x0D;
pub const VK_SHIFT = 0x10;
pub const VK_CONTROL = 0x11;
pub const VK_MENU = 0x12; // Alt
pub const VK_PAUSE = 0x13;
pub const VK_CAPITAL = 0x14; // Caps Lock
pub const VK_ESCAPE = 0x1B;
pub const VK_SPACE = 0x20;
pub const VK_PRIOR = 0x21; // Page Up
pub const VK_NEXT = 0x22; // Page Down
pub const VK_END = 0x23;
pub const VK_HOME = 0x24;
pub const VK_LEFT = 0x25;
pub const VK_UP = 0x26;
pub const VK_RIGHT = 0x27;
pub const VK_DOWN = 0x28;
pub const VK_INSERT = 0x2D;
pub const VK_DELETE = 0x2E;
pub const VK_LWIN = 0x5B;
pub const VK_RWIN = 0x5C;
pub const VK_F1 = 0x70;
pub const VK_F2 = 0x71;
pub const VK_F3 = 0x72;
pub const VK_F4 = 0x73;
pub const VK_F5 = 0x74;
pub const VK_F6 = 0x75;
pub const VK_F7 = 0x76;
pub const VK_F8 = 0x77;
pub const VK_F9 = 0x78;
pub const VK_F10 = 0x79;
pub const VK_F11 = 0x7A;
pub const VK_F12 = 0x7B;
pub const VK_NUMLOCK = 0x90;
pub const VK_SCROLL = 0x91;
pub const VK_LSHIFT = 0xA0;
pub const VK_RSHIFT = 0xA1;
pub const VK_LCONTROL = 0xA2;
pub const VK_RCONTROL = 0xA3;
pub const VK_LMENU = 0xA4;
pub const VK_RMENU = 0xA5;
pub const VK_OEM_1 = 0xBA; // ;:
pub const VK_OEM_PLUS = 0xBB;
pub const VK_OEM_COMMA = 0xBC;
pub const VK_OEM_MINUS = 0xBD;
pub const VK_OEM_PERIOD = 0xBE;
pub const VK_OEM_2 = 0xBF; // /?
pub const VK_OEM_3 = 0xC0; // `~
pub const VK_OEM_4 = 0xDB; // [{
pub const VK_OEM_5 = 0xDC; // \|
pub const VK_OEM_6 = 0xDD; // ]}
pub const VK_OEM_7 = 0xDE; // '"

// GetKeyState constants
pub const KEY_STATE_DOWN: i16 = -128; // 0x80 in high bit

// MAPVK constants
pub const MAPVK_VK_TO_VSC = 0;
pub const MAPVK_VSC_TO_VK = 1;
pub const MAPVK_VK_TO_CHAR = 2;

// DPI awareness
pub const USER_DEFAULT_SCREEN_DPI = 96;

// -------- user32.dll --------

pub extern "user32" fn RegisterClassExW(lpWndClass: *const WNDCLASSEXW) callconv(.c) ATOM;
pub extern "user32" fn CreateWindowExW(
    dwExStyle: DWORD,
    lpClassName: LPCWSTR,
    lpWindowName: LPCWSTR,
    dwStyle: DWORD,
    x: c_int,
    y: c_int,
    nWidth: c_int,
    nHeight: c_int,
    hWndParent: ?HWND,
    hMenu: ?HMENU,
    hInstance: ?HINSTANCE,
    lpParam: ?*anyopaque,
) callconv(.c) ?HWND;
pub extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.c) BOOL;
pub extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: c_int) callconv(.c) BOOL;
pub extern "user32" fn UpdateWindow(hWnd: HWND) callconv(.c) BOOL;
pub extern "user32" fn GetMessageW(lpMsg: *MSG, hWnd: ?HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT) callconv(.c) BOOL;
pub extern "user32" fn PeekMessageW(lpMsg: *MSG, hWnd: ?HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT, wRemoveMsg: UINT) callconv(.c) BOOL;
pub extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.c) BOOL;
pub extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(.c) LRESULT;
pub extern "user32" fn PostMessageW(hWnd: ?HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.c) BOOL;
pub extern "user32" fn PostQuitMessage(nExitCode: c_int) callconv(.c) void;
pub extern "user32" fn DefWindowProcW(hWnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.c) LRESULT;
pub extern "user32" fn GetClientRect(hWnd: HWND, lpRect: *RECT) callconv(.c) BOOL;
pub extern "user32" fn GetWindowRect(hWnd: HWND, lpRect: *RECT) callconv(.c) BOOL;
pub extern "user32" fn GetDC(hWnd: ?HWND) callconv(.c) ?HDC;
pub extern "user32" fn ReleaseDC(hWnd: ?HWND, hDC: HDC) callconv(.c) c_int;
pub extern "user32" fn SetWindowTextW(hWnd: HWND, lpString: LPCWSTR) callconv(.c) BOOL;
pub extern "user32" fn InvalidateRect(hWnd: ?HWND, lpRect: ?*const RECT, bErase: BOOL) callconv(.c) BOOL;
pub extern "user32" fn ValidateRect(hWnd: ?HWND, lpRect: ?*const RECT) callconv(.c) BOOL;
pub extern "user32" fn LoadCursorW(hInstance: ?HINSTANCE, lpCursorName: LPCWSTR) callconv(.c) ?HCURSOR;
pub extern "user32" fn SetCursor(hCursor: ?HCURSOR) callconv(.c) ?HCURSOR;
pub extern "user32" fn GetCursorPos(lpPoint: *POINT) callconv(.c) BOOL;
pub extern "user32" fn ScreenToClient(hWnd: HWND, lpPoint: *POINT) callconv(.c) BOOL;
pub extern "user32" fn GetKeyState(nVirtKey: c_int) callconv(.c) i16;
pub extern "user32" fn MapVirtualKeyW(uCode: UINT, uMapType: UINT) callconv(.c) UINT;
pub extern "user32" fn ToUnicodeEx(
    wVirtKey: UINT,
    wScanCode: UINT,
    lpKeyState: [*]const BYTE,
    pwszBuff: [*]u16,
    cchBuff: c_int,
    wFlags: UINT,
    dwhkl: ?*anyopaque, // HKL
) callconv(.c) c_int;
pub extern "user32" fn GetKeyboardState(lpKeyState: [*]BYTE) callconv(.c) BOOL;
pub extern "user32" fn GetDpiForWindow(hWnd: HWND) callconv(.c) UINT;
pub extern "user32" fn AdjustWindowRectEx(lpRect: *RECT, dwStyle: DWORD, bMenu: BOOL, dwExStyle: DWORD) callconv(.c) BOOL;
pub extern "user32" fn SetWindowPos(
    hWnd: HWND,
    hWndInsertAfter: ?HWND,
    x: c_int,
    y: c_int,
    cx: c_int,
    cy: c_int,
    uFlags: UINT,
) callconv(.c) BOOL;
pub extern "user32" fn SetWindowLongPtrW(hWnd: HWND, nIndex: c_int, dwNewLong: isize) callconv(.c) isize;
pub extern "user32" fn GetWindowLongPtrW(hWnd: HWND, nIndex: c_int) callconv(.c) isize;
pub extern "user32" fn SetForegroundWindow(hWnd: HWND) callconv(.c) BOOL;
pub extern "user32" fn IsIconic(hWnd: HWND) callconv(.c) BOOL;
pub extern "user32" fn IsZoomed(hWnd: HWND) callconv(.c) BOOL;
pub extern "user32" fn MonitorFromWindow(hWnd: ?HWND, dwFlags: DWORD) callconv(.c) ?HMONITOR;
pub extern "user32" fn GetMonitorInfoW(hMonitor: HMONITOR, lpmi: *MONITORINFO) callconv(.c) BOOL;
pub extern "user32" fn MessageBeep(uType: UINT) callconv(.c) BOOL;
pub extern "user32" fn MessageBoxW(hWnd: ?HWND, lpText: LPCWSTR, lpCaption: LPCWSTR, uType: UINT) callconv(.c) c_int;
pub extern "user32" fn FlashWindowEx(pfwi: *FLASHWINFO) callconv(.c) BOOL;
pub extern "user32" fn SetCapture(hWnd: HWND) callconv(.c) ?HWND;
pub extern "user32" fn ReleaseCapture() callconv(.c) BOOL;

pub extern "user32" fn OpenClipboard(hWndNewOwner: ?HWND) callconv(.c) BOOL;
pub extern "user32" fn CloseClipboard() callconv(.c) BOOL;
pub extern "user32" fn GetClipboardData(uFormat: UINT) callconv(.c) ?*anyopaque;
pub extern "user32" fn SetClipboardData(uFormat: UINT, hMem: ?*anyopaque) callconv(.c) ?*anyopaque;
pub extern "user32" fn EmptyClipboard() callconv(.c) BOOL;

pub const CF_UNICODETEXT: UINT = 13;

// SetWindowLongPtr indices
pub const GWLP_USERDATA: c_int = -21;
pub const GWLP_STYLE: c_int = -16;

// SetWindowPos flags
pub const SWP_NOSIZE: UINT = 0x0001;
pub const SWP_NOMOVE: UINT = 0x0002;
pub const SWP_NOZORDER: UINT = 0x0004;
pub const SWP_FRAMECHANGED: UINT = 0x0020;

// Special HWND values for SetWindowPos
pub const HWND_TOPMOST: ?HWND = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));
pub const HWND_NOTOPMOST: ?HWND = @ptrFromInt(@as(usize, @bitCast(@as(isize, -2))));

// Monitor lookup
pub const MONITOR_DEFAULTTONEAREST: DWORD = 0x00000002;

// -------- imm32.dll --------

pub extern "imm32" fn ImmGetContext(hWnd: HWND) callconv(.c) ?HIMC;
pub extern "imm32" fn ImmReleaseContext(hWnd: HWND, hIMC: HIMC) callconv(.c) BOOL;
pub extern "imm32" fn ImmGetOpenStatus(hIMC: HIMC) callconv(.c) BOOL;
pub extern "imm32" fn ImmGetCompositionStringW(
    hIMC: HIMC,
    dwIndex: DWORD,
    lpBuf: LPVOID,
    dwBufLen: DWORD,
) callconv(.c) LONG;
pub extern "imm32" fn ImmSetCompositionWindow(
    hIMC: HIMC,
    lpCompForm: *const COMPOSITIONFORM,
) callconv(.c) BOOL;
pub extern "imm32" fn ImmSetCandidateWindow(
    hIMC: HIMC,
    lpCandidate: *const CANDIDATEFORM,
) callconv(.c) BOOL;

// MessageBox flags and return values
pub const MB_OKCANCEL: UINT = 0x00000001;
pub const MB_ICONWARNING: UINT = 0x00000030;
pub const IDOK: c_int = 1;

// FlashWindowEx flags
pub const FLASHW_STOP: DWORD = 0;
pub const FLASHW_CAPTION: DWORD = 0x00000001;
pub const FLASHW_TRAY: DWORD = 0x00000002;
pub const FLASHW_TIMERNOFG: DWORD = 0x0000000C;

// PeekMessage flags
pub const PM_REMOVE: UINT = 0x0001;

// -------- gdi32.dll --------

pub extern "gdi32" fn ChoosePixelFormat(hdc: HDC, ppfd: *const PIXELFORMATDESCRIPTOR) callconv(.c) c_int;
pub extern "gdi32" fn SetPixelFormat(hdc: HDC, format: c_int, ppfd: *const PIXELFORMATDESCRIPTOR) callconv(.c) BOOL;
pub extern "gdi32" fn DescribePixelFormat(hdc: HDC, iPixelFormat: c_int, nBytes: UINT, ppfd: *PIXELFORMATDESCRIPTOR) callconv(.c) c_int;
pub extern "gdi32" fn SwapBuffers(hdc: HDC) callconv(.c) BOOL;

// -------- opengl32.dll --------

pub extern "opengl32" fn wglCreateContext(hdc: HDC) callconv(.c) ?HGLRC;
pub extern "opengl32" fn wglDeleteContext(hglrc: HGLRC) callconv(.c) BOOL;
pub extern "opengl32" fn wglMakeCurrent(hdc: ?HDC, hglrc: ?HGLRC) callconv(.c) BOOL;
pub extern "opengl32" fn wglGetProcAddress(lpszProc: [*:0]const u8) callconv(.c) ?*const fn () callconv(.c) void;
pub extern "opengl32" fn wglGetCurrentDC() callconv(.c) ?HDC;

// WGL extension function pointers (loaded at runtime)
pub const WglChoosePixelFormatARB = *const fn (
    hdc: HDC,
    piAttribIList: [*]const c_int,
    pfAttribFList: ?[*]const f32,
    nMaxFormats: UINT,
    piFormats: [*]c_int,
    nNumFormats: *UINT,
) callconv(.c) BOOL;

pub const WglCreateContextAttribsARB = *const fn (
    hDC: HDC,
    hShareContext: ?HGLRC,
    attribList: [*]const c_int,
) callconv(.c) ?HGLRC;

pub const WglSwapIntervalEXT = *const fn (interval: c_int) callconv(.c) BOOL;

// -------- kernel32.dll --------

pub extern "kernel32" fn GetModuleHandleW(lpModuleName: ?LPCWSTR) callconv(.c) ?HINSTANCE;
pub extern "kernel32" fn GlobalAlloc(uFlags: UINT, dwBytes: usize) callconv(.c) ?*anyopaque;
pub extern "kernel32" fn GlobalLock(hMem: *anyopaque) callconv(.c) ?[*]u8;
pub extern "kernel32" fn GlobalUnlock(hMem: *anyopaque) callconv(.c) BOOL;
pub const GMEM_MOVEABLE: UINT = 0x0002;

/// Helper to create a null-terminated UTF-16 string from a UTF-8 string.
pub fn utf8ToUtf16(utf8: []const u8) ![128:0]u16 {
    var buf: [128:0]u16 = undefined;
    @memset(&buf, 0);
    const len = std.unicode.utf8ToUtf16Le(&buf, utf8) catch return error.InvalidUtf8;
    buf[len] = 0;
    return buf;
}

/// Helper to convert a UTF-16 null-terminated string to UTF-8.
pub fn utf16ToUtf8(alloc: std.mem.Allocator, utf16: [*:0]const u16) ![]u8 {
    var len: usize = 0;
    while (utf16[len] != 0) len += 1;
    return std.unicode.utf16LeToUtf8Alloc(alloc, utf16[0..len]);
}

/// Get the low word of an LPARAM.
pub fn loword(l: LPARAM) i16 {
    return @truncate(@as(isize, @bitCast(l)));
}

/// Get the high word of an LPARAM.
pub fn hiword(l: LPARAM) i16 {
    return @truncate(@as(isize, @bitCast(l)) >> 16);
}

/// Get the low word of a WPARAM.
pub fn lowordW(w: WPARAM) u16 {
    return @truncate(w);
}

/// Get the high word of a WPARAM.
pub fn hiwordW(w: WPARAM) i16 {
    return @truncate(@as(isize, @bitCast(w)) >> 16);
}

/// GET_X_LPARAM / GET_Y_LPARAM
pub fn getXLparam(l: LPARAM) f32 {
    return @floatFromInt(loword(l));
}

pub fn getYLparam(l: LPARAM) f32 {
    return @floatFromInt(hiword(l));
}
