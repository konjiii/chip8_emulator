const std = @import("std");
const Emulator = @import("Emulator.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) {
        std.debug.print("memory leak detected!", .{});
    };
    const allocator = gpa.allocator();

    var emulator = try Emulator.init(allocator);
    defer emulator.deinit();
    try emulator.start();
}
