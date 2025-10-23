const std = @import("std");
const rl = @import("raylib");
const Chip8 = @import("Chip8.zig");
const Game = @import("Game.zig");

pub fn main() !void {
    var chip8 = Chip8.init();

    chip8.loadRom("./chip8/roms/games/Tetris [Fran Dachille, 1991].ch8") catch |err| {
        switch (err) {
            error.RomTooBig => std.debug.print("ROM file is too big to fit in memory.\n", .{}),
            else => return err,
        }
        return;
    };

    var game = try Game.init(&chip8);
    game.run();
}
