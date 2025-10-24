const std = @import("std");
const Emulator = @import("Emulator.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var emulator = try Emulator.init(allocator);
    defer emulator.deinit();
    try emulator.start();
}
