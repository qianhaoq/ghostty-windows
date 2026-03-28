const GhosttyWindowsHost = @This();

const std = @import("std");
const Config = @import("Config.zig");
const GhosttyLib = @import("GhosttyLib.zig");

exe: *std.Build.Step.Compile,
install_step: *std.Build.Step.InstallArtifact,

pub fn init(
    b: *std.Build,
    cfg: *const Config,
    lib: *const GhosttyLib,
) !GhosttyWindowsHost {
    if (cfg.target.result.os.tag != .windows) return error.UnsupportedTarget;

    const link_lib = lib.compile orelse
        return error.WindowsHostRequiresLinkableLibghostty;

    const exe = b.addExecutable(.{
        .name = "ghostty",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main_windows.zig"),
            .target = cfg.target,
            .optimize = cfg.optimize,
            .strip = cfg.strip,
            .omit_frame_pointer = cfg.strip,
            .unwind_tables = if (cfg.strip) .none else .sync,
        }),
        .use_llvm = true,
    });

    exe.subsystem = .Windows;
    exe.linkLibC();
    exe.addIncludePath(b.path("include"));
    exe.linkLibrary(link_lib);
    const system_libs = [_][]const u8{
        "user32",
        "gdi32",
        "opengl32",
        "imm32",
        "ws2_32",
        "mswsock",
    };
    for (system_libs) |lib_name| {
        exe.linkSystemLibrary(lib_name);
    }
    exe.addWin32ResourceFile(.{
        .file = b.path("dist/windows/ghostty.rc"),
    });

    return .{
        .exe = exe,
        .install_step = b.addInstallArtifact(exe, .{}),
    };
}

pub fn install(self: *const GhosttyWindowsHost) void {
    const b = self.install_step.step.owner;
    b.getInstallStep().dependOn(&self.install_step.step);
}
