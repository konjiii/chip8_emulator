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

pub fn init() Chip8 {
    return Chip8{};
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
