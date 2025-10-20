/// chip-8 emulator main module
const Chip8 = @This();

const std = @import("std");

registers: [16]u8 = @splat(0),
memory: [4096]u8 = @splat(0),
index: u16 = 0,
pc: u16 = 0x200,
stack: [16]u16 = @splat(0),
sp: u8 = 0,
delay_timer: u8 = 0,
sound_timer: u8 = 0,
keypad: [16]u8 = @splat(0),
display: [64 * 32]u32 = @splat(0),
opcode: u16 = 0,
rand: std.Random = undefined,

pub fn init() Chip8 {
    // generate random seed
    const seed = std.crypto.random.int(u64);

    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    var chip8 = Chip8{ .rand = rand };

    // define fontset
    const fontset: [80]u8 = .{
        0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
        0x20, 0x60, 0x20, 0x20, 0x70, // 1
        0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
        0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
        0x90, 0x90, 0xF0, 0x10, 0x10, // 4
        0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
        0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
        0xF0, 0x10, 0x20, 0x40, 0x40, // 7
        0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
        0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
        0xF0, 0x90, 0xF0, 0x90, 0x90, // A
        0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
        0xF0, 0x80, 0x80, 0x80, 0xF0, // C
        0xE0, 0x90, 0x90, 0x90, 0xE0, // D
        0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
        0xF0, 0x80, 0xF0, 0x80, 0x80, // F
    };

    // load fontset into memory
    std.mem.copyForwards(u8, chip8.memory[0x50 .. 0x50 + fontset.len], &fontset);

    return chip8;
}

/// Load a ROM into memory
pub fn loadRom(self: *Chip8, file_name: []const u8) !void {
    const file = try std.fs.cwd().openFile(file_name, .{});
    defer file.close();

    var buffer: [4096 - 0x200]u8 = undefined;
    var file_reader = file.reader(&buffer);
    const reader = &file_reader.interface;

    const stats = try file.stat();
    if (stats.size > buffer.len) {
        return error.RomTooBig;
    }

    _ = try reader.readSliceShort(self.memory[512..]);
}

pub fn randByte(self: *Chip8) u8 {
    return self.rand.int(u8);
}
