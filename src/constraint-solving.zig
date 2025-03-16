/// File to drive unit tests for all modules.
const std = @import("std");

pub const ac3 = @import("ac3.zig");
pub const mc = @import("min-conflicts.zig");
pub const bt = @import("back-tracking.zig");
pub const cmn = @import("common.zig");

test "all tests" {
    std.testing.refAllDecls(@This());
}
