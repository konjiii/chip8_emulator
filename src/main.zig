const std = @import("std");
const Chip8 = @import("Chip8.zig");

pub fn main() !void {
    var chip8 = Chip8.init();

    chip8.loadRom("PONG.ch8") catch |err| {
        std.debug.print("Failed to load ROM: {}\n", .{err});
        return;
    };
}
