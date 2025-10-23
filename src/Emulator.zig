//! Chip8 Emulator using Raylib for graphics and input handling.
const Emulator = @This();

const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const Chip8 = @import("Chip8.zig");

const FOREGROUND_CLR = rl.Color.white;
const BACKGROUND_CLR = rl.Color.black;
const BORDER_CLR = rl.Color.dark_gray;

const View = enum {
    MAIN_MENU,
    GAME,
    EXIT,
};

chip8: Chip8,
curr_rom: []const u8 = "",
virtual_width: i32 = 64 * 20,
virtual_height: i32 = 32 * 20,
window_title: [:0]const u8 = "Chip8 Emulator",
current_view: View = View.MAIN_MENU,
pixel_dim: i32 = 10,
screen_texture: rl.Texture = undefined,
fps: i32 = 60,
cpu_clock: i32 = 500, // approx
cycles_per_frame: i32 = undefined,
// map keyboard keys to Chip8 keys
comptime key_map: [16]rl.KeyboardKey = .{
    rl.KeyboardKey.x, // Key 0
    rl.KeyboardKey.one, // Key 1
    rl.KeyboardKey.two, // Key 2
    rl.KeyboardKey.three, // Key 3
    rl.KeyboardKey.q, // Key 4
    rl.KeyboardKey.w, // Key 5
    rl.KeyboardKey.e, // Key 6
    rl.KeyboardKey.a, // Key 7
    rl.KeyboardKey.s, // Key 8
    rl.KeyboardKey.d, // Key 9
    rl.KeyboardKey.z, // Key A
    rl.KeyboardKey.c, // Key B
    rl.KeyboardKey.four, // Key C
    rl.KeyboardKey.r, // Key D
    rl.KeyboardKey.f, // Key E
    rl.KeyboardKey.v, // Key F
},

pub fn init() !Emulator {
    var chip8 = Chip8.init();
    chip8.loadRom("./chip8/roms/games/Tetris [Fran Dachille, 1991].ch8") catch |err| {
        switch (err) {
            error.RomTooBig => std.debug.print("ROM file is too big to fit in memory.\n", .{}),
            else => return err,
        }
    };

    var emulator = Emulator{
        .chip8 = chip8,
    };

    emulator.cycles_per_frame = @divTrunc(emulator.cpu_clock, emulator.fps);

    rl.setConfigFlags(rl.ConfigFlags{ .window_resizable = true });

    return emulator;
}

/// emulator entry point
pub fn start(self: *Emulator) !void {
    // initialize raylib window
    rl.initWindow(self.virtual_width, self.virtual_height, self.window_title);
    defer rl.closeWindow();

    rl.setTargetFPS(self.fps);

    // create a blank texture for the Chip8 display
    const image = rl.genImageColor(Chip8.DISPLAY_WIDTH, Chip8.DISPLAY_HEIGHT, rl.Color.black);

    // load the texture from the image
    self.screen_texture = try rl.loadTextureFromImage(image);
    rl.unloadImage(image);

    while (!rl.windowShouldClose()) {
        switch (self.current_view) {
            .MAIN_MENU => {
                self.main_menu();
            },
            .GAME => {
                self.emulate();
            },
            .EXIT => {
                break;
            },
        }
    }
}

/// main menu view
pub fn main_menu(self: *Emulator) void {
    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(BORDER_CLR);

    const screen_width_f: f32 = @floatFromInt(rl.getScreenWidth());
    const screen_height_f: f32 = @floatFromInt(rl.getScreenHeight());
    const virtual_width_f: f32 = @floatFromInt(self.virtual_width);
    const virtual_height_f: f32 = @floatFromInt(self.virtual_height);

    const scale: f32 = @min(
        screen_width_f / virtual_width_f,
        screen_height_f / virtual_height_f,
    );

    const button_width: f32 = 200 * scale;
    const button_height: f32 = 50 * scale;

    const font_size: i32 = @intFromFloat(20 * scale);
    rg.setStyle(rg.Control.default, rg.ControlOrDefaultProperty{ .default = rg.DefaultProperty.text_size }, font_size);

    const start_button_rec = rl.Rectangle{
        .x = @divTrunc(screen_width_f - button_width, 2),
        .y = @divTrunc(screen_height_f - button_height, 2) - 30 * scale,
        .width = button_width,
        .height = button_height,
    };

    if (rg.button(start_button_rec, "Start Game")) {
        self.current_view = View.GAME;
    }

    const exit_button_rec = rl.Rectangle{
        .x = @divTrunc(screen_width_f - button_width, 2),
        .y = @divTrunc(screen_height_f - button_height, 2) + 40 * scale,
        .width = button_width,
        .height = button_height,
    };

    if (rg.button(exit_button_rec, "Exit")) {
        self.current_view = View.EXIT;
    }
}

/// run the main emulation loop
pub fn emulate(self: *Emulator) void {
    self.handleInput();

    // cycle cpu multiple times per frame
    self.chip8.cycle(self.cycles_per_frame);
    // update timers at 60Hz
    self.chip8.updateTimers();

    const screen_width_f: f32 = @floatFromInt(rl.getScreenWidth());
    const screen_height_f: f32 = @floatFromInt(rl.getScreenHeight());
    const virtual_width_f: f32 = @floatFromInt(self.virtual_width);
    const virtual_height_f: f32 = @floatFromInt(self.virtual_height);

    // scale virtual screen to window size while maintaining aspect ratio
    const scale: f32 = @min(
        screen_width_f / virtual_width_f,
        screen_height_f / virtual_height_f,
    );
    const dest_rec_width = virtual_width_f * scale;
    const dest_rec_height = virtual_height_f * scale;

    // parameters for drawTexturePro
    const source_rec = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = Chip8.DISPLAY_WIDTH,
        .height = Chip8.DISPLAY_HEIGHT,
    };
    const dest_rec = rl.Rectangle{
        .x = (screen_width_f - dest_rec_width) / 2,
        .y = (screen_height_f - dest_rec_height) / 2,
        .width = dest_rec_width,
        .height = dest_rec_height,
    };
    const origin = rl.Vector2{ .x = 0, .y = 0 };

    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(BORDER_CLR);

    // update the texture with the current display data
    rl.updateTexture(self.screen_texture, &self.chip8.display);
    // draw the texture scaled to the window
    self.screen_texture.drawPro(
        source_rec,
        dest_rec,
        origin,
        0,
        FOREGROUND_CLR,
    );
    rl.drawFPS(10, 10);
}

pub fn handleInput(self: *Emulator) void {
    for (0.., self.key_map) |idx, key| {
        self.chip8.keypad[idx] = rl.isKeyDown(key);
    }
}
