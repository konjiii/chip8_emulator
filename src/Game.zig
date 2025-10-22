const Game = @This();

const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const Chip8 = @import("Chip8.zig");

chip8: *Chip8,
screen_width: i32 = 64 * 10,
screen_height: i32 = 32 * 10,
window_title: [:0]const u8 = "Chip8 Emulator",
pixel_dim: i32 = 10,
foreground_color: rl.Color = rl.Color.white,
background_color: rl.Color = rl.Color.black,

pub fn init(chip8: *Chip8) Game {
    return Game{
        .chip8 = chip8,
    };
}

pub fn run(self: *Game) void {
    rl.initWindow(self.screen_width, self.screen_height, self.window_title);

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();

        self.chip8.cycle();
        self.drawDisplay();

        rl.clearBackground(rl.Color.black);

        rl.endDrawing();
    }

    rl.closeWindow();
}

fn drawDisplay(self: *const Game) void {
    for (0.., self.chip8.display) |idx, pixel| {
        if (pixel) {
            const posX: i32 = @as(i32, @intCast(idx % Chip8.DISPLAY_WIDTH)) * self.pixel_dim;
            const posY: i32 = @as(i32, @intCast(idx / Chip8.DISPLAY_WIDTH)) * self.pixel_dim;
            rl.drawRectangle(posX, posY, self.pixel_dim, self.pixel_dim, self.foreground_color);
        }
    }
}
