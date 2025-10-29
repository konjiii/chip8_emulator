//! Chip8 Emulator using Raylib for graphics and input handling.
const Emulator = @This();

const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const nfd = @import("nfd");
const Chip8 = @import("Chip8.zig");
const Audio = @import("Audio.zig");

const FOREGROUND_CLR = rl.Color.white;
const BACKGROUND_CLR = rl.Color.black;
const BORDER_CLR = rl.Color.dark_gray;

const View = enum {
    MAIN_MENU,
    GAME,
    EXIT,
};

chip8: Chip8,
curr_rom: [:0]const u8 = "",
allocator: std.mem.Allocator,
virtual_width: i32 = 64 * 20,
virtual_height: i32 = 32 * 20,
window_title: [:0]const u8 = "Chip8 Emulator",
current_view: View = View.MAIN_MENU,
pixel_dim: i32 = 10,
screen_texture: rl.Texture = undefined,
fps: i32 = 60,
cpu_clock: i32 = 500, // approx
cycles_per_frame: i32 = undefined,
audio: Audio = undefined,

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

pub fn init(allocator: std.mem.Allocator) !Emulator {
    const chip8 = Chip8.init();

    var emulator = Emulator{
        .chip8 = chip8,
        .allocator = allocator,
    };

    emulator.cycles_per_frame = @divTrunc(emulator.cpu_clock, emulator.fps);

    rl.setConfigFlags(rl.ConfigFlags{ .window_resizable = true });

    return emulator;
}

pub fn deinit(self: *Emulator) void {
    if (self.curr_rom.len != 0) {
        self.allocator.free(self.curr_rom);
    }
}

/// load rom into chip8 memory
fn loadRom(self: *Emulator, path: []const u8) !void {
    try self.chip8.loadRom(path);
    const file_name = std.fs.path.basename(path);
    self.curr_rom = try self.allocator.dupeZ(u8, file_name);
}

/// emulator entry point
pub fn start(self: *Emulator) !void {
    // initialize raylib window
    rl.initWindow(self.virtual_width, self.virtual_height, self.window_title);
    defer rl.closeWindow();

    rl.setTargetFPS(self.fps);

    // initialize audio stream
    self.audio = Audio.init();
    defer self.audio.deinit();

    // create a blank texture for the Chip8 display
    const image = rl.genImageColor(Chip8.DISPLAY_WIDTH, Chip8.DISPLAY_HEIGHT, rl.Color.black);

    // load the texture from the image
    self.screen_texture = try rl.loadTextureFromImage(image);
    defer rl.unloadTexture(self.screen_texture);
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

    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(BORDER_CLR);

    const font_size: i32 = @intFromFloat(20 * scale);
    // label font size
    rg.setStyle(rg.Control.default, rg.ControlOrDefaultProperty{ .default = rg.DefaultProperty.text_size }, font_size * 2);

    const title_label_rec = rl.Rectangle{
        .x = (screen_width_f - button_width * 1.5) / 2,
        .y = 60 * scale,
        .width = button_width * 1.5,
        .height = button_height,
    };

    _ = rg.label(title_label_rec, "Chip-8 Emulator");

    // button font size
    rg.setStyle(rg.Control.default, rg.ControlOrDefaultProperty{ .default = rg.DefaultProperty.text_size }, font_size);

    const start_button_rec = rl.Rectangle{
        .x = (screen_width_f - button_width) / 2,
        .y = (screen_height_f - button_height) / 2 - 60 * scale,
        .width = button_width,
        .height = button_height,
    };

    if (rg.button(start_button_rec, "Start Game")) {
        if (self.curr_rom.len == 0) {
            return;
        }
        self.current_view = View.GAME;
    }

    const select_button_rec = rl.Rectangle{
        .x = (screen_width_f - button_width) / 2,
        .y = (screen_height_f - button_height) / 2,
        .width = button_width,
        .height = button_height,
    };

    if (rg.button(select_button_rec, "Select ROM")) {
        const file_path = nfd.openFileDialog("ch8", ".") catch {
            return;
        };

        if (file_path) |path| {
            self.loadRom(path) catch |err| {
                std.debug.print("Failed to load ROM: {}\n", .{err});
                return;
            };
        }
    }

    const curr_rom_label_rec = rl.Rectangle{
        .x = (screen_width_f) / 2 + button_width / 2 + 10 * scale,
        .y = (screen_height_f - button_height) / 2,
        .width = screen_width_f - ((screen_width_f) / 2 + button_width / 2 + 10 * scale),
        .height = button_height,
    };

    _ = rg.label(curr_rom_label_rec, if (self.curr_rom.len == 0) "No ROM selected" else self.curr_rom);

    const exit_button_rec = rl.Rectangle{
        .x = (screen_width_f - button_width) / 2,
        .y = (screen_height_f - button_height) / 2 + 60 * scale,
        .width = button_width,
        .height = button_height,
    };

    if (rg.button(exit_button_rec, "Exit")) {
        self.current_view = View.EXIT;
    }
}

/// run the main emulation loop
pub fn emulate(self: *Emulator) void {
    // -- input handling --
    self.handleInput();

    // -- emulation --
    // cycle cpu multiple times per frame
    self.chip8.cycle(self.cycles_per_frame);
    // update timers at 60Hz
    self.chip8.updateTimers();

    // -- audio --
    if (self.chip8.sound_timer > 0) {
        self.audio.play();
    } else {
        self.audio.stop();
    }

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

    // -- drawing --
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
