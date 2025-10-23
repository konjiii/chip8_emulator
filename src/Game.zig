const Game = @This();

const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const Chip8 = @import("Chip8.zig");

const FOREGROUND_CLR = rl.Color.white;
const BACKGROUND_CLR = rl.Color.black;
const BORDER_CLR = rl.Color.dark_gray;

chip8: *Chip8,
virtual_width: i32 = 64 * 20,
virtual_height: i32 = 32 * 20,
window_title: [:0]const u8 = "Chip8 Emulator",
pixel_dim: i32 = 10,
screen_texture: rl.Texture = undefined,

pub fn init(chip8: *Chip8) !Game {
    var game = Game{
        .chip8 = chip8,
    };

    rl.setConfigFlags(rl.ConfigFlags{ .window_resizable = true });
    // initialize raylib window
    rl.initWindow(game.virtual_width, game.virtual_height, game.window_title);

    // create a blank texture for the Chip8 display
    const image = rl.genImageColor(Chip8.DISPLAY_WIDTH, Chip8.DISPLAY_HEIGHT, rl.Color.black);
    defer rl.unloadImage(image);

    // load the texture from the image
    game.screen_texture = try rl.loadTextureFromImage(image);

    return game;
}

pub fn run(self: *Game) void {
    // parameters for drawing the texture
    const source_rec = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = Chip8.DISPLAY_WIDTH,
        .height = Chip8.DISPLAY_HEIGHT,
    };
    var dest_rec = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(self.virtual_width),
        .height = @floatFromInt(self.virtual_height),
    };
    const origin = rl.Vector2{ .x = 0, .y = 0 };

    rl.setTargetFPS(60);

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(BORDER_CLR);

        self.chip8.cycle();

        const screen_width_f: f32 = @floatFromInt(rl.getScreenWidth());
        const screen_height_f: f32 = @floatFromInt(rl.getScreenHeight());
        const virtual_width_f: f32 = @floatFromInt(self.virtual_width);
        const virtual_height_f: f32 = @floatFromInt(self.virtual_height);

        // scale virtual screen to window size while maintaining aspect ratio
        const scale: f32 = @min(
            screen_width_f / virtual_width_f,
            screen_height_f / virtual_height_f,
        );
        dest_rec.width = virtual_width_f * scale;
        dest_rec.height = virtual_height_f * scale;

        // center the destination rectangle
        dest_rec.x = (screen_width_f - dest_rec.width) / 2;
        dest_rec.y = (screen_height_f - dest_rec.height) / 2;

        // update the texture with the current display data
        rl.updateTexture(self.screen_texture, &self.chip8.display);
        // draw the texture scaled to the window
        rl.drawTexturePro(
            self.screen_texture, // texture to draw
            source_rec,
            dest_rec,
            origin,
            0, // rotation
            FOREGROUND_CLR, // draw color
        );
    }

    rl.closeWindow();
}
