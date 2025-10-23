const std = @import("std");
const Emulator = @import("Emulator.zig");

pub fn main() !void {
    var emulator = try Emulator.init();
    try emulator.start();
}
