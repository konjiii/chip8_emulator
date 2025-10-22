const std = @import("std");
const Chip8 = @import("Chip8.zig");

pub fn main() !void {
    var chip8 = Chip8.init();

    chip8.loadRom("./chip8/roms/games/Cave.ch8") catch |err| {
        switch (err) {
            error.RomTooBig => std.debug.print("ROM file is too big to fit in memory.\n", .{}),
            else => return err,
        }
        return;
    };
}
