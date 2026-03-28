/// WGL OpenGL context management for Windows.
/// Uses the two-step process to create a modern OpenGL 4.3+ Core Profile context.
const wgl = @This();

const std = @import("std");
const win32 = @import("win32.zig");

const log = std.log.scoped(.wgl);

pub const Context = struct {
    hdc: win32.HDC,
    hglrc: win32.HGLRC,

    // Extension function pointers (loaded from bootstrap context)
    wglChoosePixelFormatARB: ?win32.WglChoosePixelFormatARB = null,
    wglCreateContextAttribsARB: ?win32.WglCreateContextAttribsARB = null,
    wglSwapIntervalEXT: ?win32.WglSwapIntervalEXT = null,

    /// Create a modern OpenGL context on the given window's DC.
    /// This uses the two-step bootstrap process:
    /// 1. Create temporary context with basic pixel format to load WGL extensions
    /// 2. Use extensions to create proper context with desired attributes
    pub fn init(hwnd: win32.HWND) !Context {
        const hdc = win32.GetDC(hwnd) orelse return error.GetDCFailed;
        errdefer _ = win32.ReleaseDC(hwnd, hdc);

        // Step 1: Set a basic pixel format to create bootstrap context
        var pfd = win32.PIXELFORMATDESCRIPTOR{
            .dwFlags = win32.PFD_DRAW_TO_WINDOW | win32.PFD_SUPPORT_OPENGL | win32.PFD_DOUBLEBUFFER,
            .iPixelType = win32.PFD_TYPE_RGBA,
            .cColorBits = 32,
            .cDepthBits = 24,
            .cStencilBits = 8,
            .iLayerType = win32.PFD_MAIN_PLANE,
        };

        const pixel_format = win32.ChoosePixelFormat(hdc, &pfd);
        if (pixel_format == 0) return error.ChoosePixelFormatFailed;

        if (win32.SetPixelFormat(hdc, pixel_format, &pfd) == 0)
            return error.SetPixelFormatFailed;

        // Create bootstrap context
        const temp_ctx = win32.wglCreateContext(hdc) orelse
            return error.WglCreateContextFailed;

        if (win32.wglMakeCurrent(hdc, temp_ctx) == 0) {
            _ = win32.wglDeleteContext(temp_ctx);
            return error.WglMakeCurrentFailed;
        }

        // Load WGL extension functions
        const wglChoosePixelFormatARB: ?win32.WglChoosePixelFormatARB =
            @ptrCast(win32.wglGetProcAddress("wglChoosePixelFormatARB"));
        const wglCreateContextAttribsARB: ?win32.WglCreateContextAttribsARB =
            @ptrCast(win32.wglGetProcAddress("wglCreateContextAttribsARB"));
        const wglSwapIntervalEXT: ?win32.WglSwapIntervalEXT =
            @ptrCast(win32.wglGetProcAddress("wglSwapIntervalEXT"));

        // Step 2: Create modern context if extensions are available
        if (wglCreateContextAttribsARB) |createCtx| {
            const attribs = [_]c_int{
                win32.WGL_CONTEXT_MAJOR_VERSION_ARB, 4,
                win32.WGL_CONTEXT_MINOR_VERSION_ARB, 3,
                win32.WGL_CONTEXT_PROFILE_MASK_ARB, win32.WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
                0, // terminator
            };

            // Release and delete bootstrap context before creating modern one
            _ = win32.wglMakeCurrent(null, null);
            _ = win32.wglDeleteContext(temp_ctx);

            const modern_ctx = createCtx(hdc, null, &attribs) orelse {
                log.warn("failed to create OpenGL 4.3 core context, falling back", .{});
                return error.ModernContextFailed;
            };

            // Activate modern context
            if (win32.wglMakeCurrent(hdc, modern_ctx) == 0) {
                _ = win32.wglDeleteContext(modern_ctx);
                return error.WglMakeCurrentFailed;
            }

            // Enable vsync if available
            if (wglSwapIntervalEXT) |swapInterval| {
                _ = swapInterval(1);
            }

            log.info("created OpenGL 4.3 Core Profile context", .{});

            return .{
                .hdc = hdc,
                .hglrc = modern_ctx,
                .wglChoosePixelFormatARB = wglChoosePixelFormatARB,
                .wglCreateContextAttribsARB = wglCreateContextAttribsARB,
                .wglSwapIntervalEXT = wglSwapIntervalEXT,
            };
        }

        // Extensions not available, clean up bootstrap context
        _ = win32.wglMakeCurrent(null, null);
        _ = win32.wglDeleteContext(temp_ctx);
        return error.WglExtensionsNotAvailable;
    }

    /// Make this context current on the calling thread.
    pub fn makeCurrent(self: *const Context) void {
        _ = win32.wglMakeCurrent(self.hdc, self.hglrc);
    }

    /// Release this context from the calling thread.
    pub fn release(_: *const Context) void {
        _ = win32.wglMakeCurrent(null, null);
    }

    /// Swap buffers (present the rendered frame).
    pub fn swapBuffers(self: *const Context) void {
        _ = win32.SwapBuffers(self.hdc);
    }

    /// Destroy the OpenGL context.
    pub fn deinit(self: *Context, hwnd: win32.HWND) void {
        _ = win32.wglMakeCurrent(null, null);
        _ = win32.wglDeleteContext(self.hglrc);
        _ = win32.ReleaseDC(hwnd, self.hdc);
    }
};
