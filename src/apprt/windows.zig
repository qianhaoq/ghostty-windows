// The required comptime API for any apprt.
pub const App = @import("windows/App.zig");
pub const Surface = @import("windows/Surface.zig");

const internal_os = @import("../os/main.zig");
pub const resourcesDir = internal_os.resourcesDir;
