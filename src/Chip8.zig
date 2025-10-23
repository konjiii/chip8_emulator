//! chip-8 emulator main module
const Chip8 = @This();

const std = @import("std");
const rl = @import("raylib");

pub const DISPLAY_WIDTH: u8 = 64;
pub const DISPLAY_HEIGHT: u8 = 32;
// where the fontset is stored in memory
const FONTSET_START_ADDR: u16 = 0x50;

// definition of opcode function types
const OpFn = *const fn (self: *Chip8) void;

// 16 8-bit registers: V0 to VF
registers: [16]u8 = @splat(0),
memory: [4096]u8 = @splat(0),
index: u16 = 0,
// program counter starts at 0x200 where the roms are loaded
pc: u16 = 0x200,
stack: [16]u16 = @splat(0),
sp: u8 = 0,
delay_timer: u8 = 0,
sound_timer: u8 = 0,
keypad: [16]bool = @splat(false),
display: [@as(u16, DISPLAY_WIDTH) * DISPLAY_HEIGHT]rl.Color = @splat(rl.Color.black),
opcode: u16 = 0,
rand: std.Random = undefined,
// function pointer table for quick opcode instruction lookup
comptime fn_ptr_tbl: [0xF + 1]OpFn = .{
    Chip8.dispatch0,
    Chip8.OP_1nnn,
    Chip8.OP_2nnn,
    Chip8.OP_3xkk,
    Chip8.OP_4xkk,
    Chip8.OP_5xy0,
    Chip8.OP_6xkk,
    Chip8.OP_7xkk,
    Chip8.dispatch8,
    Chip8.OP_9xy0,
    Chip8.OP_Annn,
    Chip8.OP_Bnnn,
    Chip8.OP_Cxkk,
    Chip8.OP_Dxyn,
    Chip8.dispatchE,
    Chip8.dispatchF,
},

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

    // start and end address of fontset in memory
    const start = FONTSET_START_ADDR;
    const end = FONTSET_START_ADDR + fontset.len;
    // load fontset into memory
    std.mem.copyForwards(u8, chip8.memory[start..end], &fontset);

    return chip8;
}

/// main chip8 cycle
pub fn cycle(self: *Chip8, amount: i32) void {
    for (0..@intCast(amount)) |_| {
        // obtain next opcode: 2 8-bit parts in memory
        self.opcode = (@as(u16, self.memory[self.pc]) << 8) | self.memory[self.pc + 1];

        self.pc += 2;

        const table_index = (self.opcode & 0xF000) >> 12;
        // execute the function that corresponds to the opcode
        self.fn_ptr_tbl[table_index](self);

        // decrement delay and sound timer
        self.delay_timer = if (self.delay_timer > 0) self.delay_timer - 1 else 0;
        self.sound_timer = if (self.sound_timer > 0) self.sound_timer - 1 else 0;
    }
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

    _ = try reader.readSliceShort(self.memory[0x200..]);
}

/// generate a random u8 integer
fn randByte(self: *const Chip8) u8 {
    return self.rand.int(u8);
}

// dispatch functions for nested function pointer tables
fn dispatch0(self: *Chip8) void {
    comptime var table_0: [0xE + 1]OpFn = @splat(Chip8.NOP);
    table_0[0x0] = Chip8.OP_00E0;
    table_0[0xE] = Chip8.OP_00EE;

    const last_nibble = self.opcode & 0x000F;
    table_0[last_nibble](self);
}

fn dispatch8(self: *Chip8) void {
    comptime var table_8: [0xE + 1]OpFn = @splat(Chip8.NOP);
    table_8[0x0] = Chip8.OP_8xy0;
    table_8[0x1] = Chip8.OP_8xy1;
    table_8[0x2] = Chip8.OP_8xy2;
    table_8[0x3] = Chip8.OP_8xy3;
    table_8[0x4] = Chip8.OP_8xy4;
    table_8[0x5] = Chip8.OP_8xy5;
    table_8[0x6] = Chip8.OP_8xy6;
    table_8[0x7] = Chip8.OP_8xy7;
    table_8[0xE] = Chip8.OP_8xyE;

    const last_nibble = self.opcode & 0x000F;
    table_8[last_nibble](self);
}

fn dispatchE(self: *Chip8) void {
    comptime var table_E: [0xE + 1]OpFn = @splat(Chip8.NOP);
    table_E[0x1] = Chip8.OP_ExA1;
    table_E[0xE] = Chip8.OP_Ex9E;

    const last_nibble = self.opcode & 0x000F;
    table_E[last_nibble](self);
}

fn dispatchF(self: *Chip8) void {
    comptime var table_F: [0x65 + 1]OpFn = @splat(Chip8.NOP);
    table_F[0x07] = Chip8.OP_Fx07;
    table_F[0x0A] = Chip8.OP_Fx0A;
    table_F[0x15] = Chip8.OP_Fx15;
    table_F[0x18] = Chip8.OP_Fx18;
    table_F[0x1E] = Chip8.OP_Fx1E;
    table_F[0x29] = Chip8.OP_Fx29;
    table_F[0x33] = Chip8.OP_Fx33;
    table_F[0x55] = Chip8.OP_Fx55;
    table_F[0x65] = Chip8.OP_Fx65;

    const last_nibble = self.opcode & 0x00FF;
    table_F[last_nibble](self);
}

// ====================================
// below are the 34 opcode instructions
// ====================================

/// 00E0 -> CLS: clear display
fn OP_00E0(self: *Chip8) void {
    self.display = @splat(rl.Color.black);
}

/// 00EE -> RET: return from subroutine
fn OP_00EE(self: *Chip8) void {
    self.sp -= 1;
    self.pc = self.stack[self.sp];
}

/// 1nnn -> JP addr: jump to location nnn
fn OP_1nnn(self: *Chip8) void {
    const addr: u16 = self.opcode & 0x0FFF;
    self.pc = addr;
}

/// 2nnn -> CALL addr: call subroutine at nnn
fn OP_2nnn(self: *Chip8) void {
    const addr: u16 = self.opcode & 0x0FFF;
    self.stack[self.sp] = self.pc;
    self.sp += 1;
    self.pc = addr;
}

/// 3xkk -> SE Vx, byte: skip next instruction if Vx == kk
fn OP_3xkk(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const byte: u8 = @intCast(self.opcode & 0x00FF);

    if (self.registers[Vx] == byte) {
        self.pc += 2;
    }
}

/// 4xkk -> SNE Vx, byte: skip next instruction if Vx != kk
fn OP_4xkk(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const byte: u8 = @intCast(self.opcode & 0x00FF);

    if (self.registers[Vx] != byte) {
        self.pc += 2;
    }
}

/// 5xy0 -> SE Vx, Vy: skip net instruction if Vx == Vy
fn OP_5xy0(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const Vy: u8 = @intCast((self.opcode & 0x00F0) >> 4);

    if (self.registers[Vx] == self.registers[Vy]) {
        self.pc += 2;
    }
}

/// 6xkk -> LD Vx, byte: set Vx = kk
fn OP_6xkk(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const byte: u8 = @intCast(self.opcode & 0x00FF);

    self.registers[Vx] = byte;
}

/// 7xkk -> ADD Vx, byte: set Vx = kk
fn OP_7xkk(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);

    // +% wraps when overflow
    self.registers[Vx] +%= @intCast(self.opcode & 0x00FF);
}

/// 8xy0 -> LD Vx, Vy: set Vx = Vy
fn OP_8xy0(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const Vy: u8 = @intCast((self.opcode & 0x00F0) >> 4);

    self.registers[Vx] = self.registers[Vy];
}

/// 8xy1 -> OR Vx, Vy: set Vx = Vx OR Vy
fn OP_8xy1(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const Vy: u8 = @intCast((self.opcode & 0x00F0) >> 4);

    self.registers[Vx] |= self.registers[Vy];
}

/// 8xy2 -> AND Vx, Vy: set Vx = Vx AND Vy
fn OP_8xy2(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const Vy: u8 = @intCast((self.opcode & 0x00F0) >> 4);

    self.registers[Vx] &= self.registers[Vy];
}

/// 8xy3 -> XOR Vx, Vy: set Vx = Vx XOR Vy
fn OP_8xy3(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const Vy: u8 = @intCast((self.opcode & 0x00F0) >> 4);

    self.registers[Vx] ^= self.registers[Vy];
}

/// 8xy4 -> ADD Vx, Vy: set Vx = Vx + Vy, set VF = carry
/// add with overflow. VF is set to 1 if result greater than 8 bits
fn OP_8xy4(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const Vy: u8 = @intCast((self.opcode & 0x00F0) >> 4);

    self.registers[Vx], self.registers[0xF] = @addWithOverflow(self.registers[Vx], self.registers[Vy]);
}

/// 8xy5 -> SUB VX, Vy: set Vx = Vx - Vy, set VF = NOT borrow
/// sub with overflow. if Vx > Vy, then VF is set to 1, otherwise 0
fn OP_8xy5(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const Vy: u8 = @intCast((self.opcode & 0x00F0) >> 4);

    self.registers[Vx], self.registers[0xF] = @subWithOverflow(self.registers[Vx], self.registers[Vy]);
}

/// 8xy6 -> SHR Vx: set Vx = Vx SHR 1
/// right shift (div by 2) with overflow of least significant bit
fn OP_8xy6(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);

    self.registers[0xF] = self.registers[Vx] & 0x1;
    self.registers[Vx] >>= 1;
}

/// 8xy7 -> SUBN Vx, Vy: set Vx = Vy - Vx, set VF = NOT borrow
/// sub with overflow. if Vy > Vx, then VF is set to 1, otherwise 0
fn OP_8xy7(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const Vy: u8 = @intCast((self.opcode & 0x00F0) >> 4);

    self.registers[Vx], self.registers[0xF] = @subWithOverflow(self.registers[Vy], self.registers[Vx]);
}

/// 8xyE -> SHL Vx: set Vx = Vx SHL 1
/// left shift (mult by 2) with overflow
fn OP_8xyE(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);

    self.registers[Vx], self.registers[0xF] = @shlWithOverflow(self.registers[Vx], 1);
}

/// 9xy0 -> SNE Vx, Vy: skip next instruction if Vx != Vy
fn OP_9xy0(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const Vy: u8 = @intCast((self.opcode & 0x00F0) >> 4);

    if (self.registers[Vx] != self.registers[Vy]) {
        self.pc += 2;
    }
}

/// Annn -> LD I, addr: set I = nnn
fn OP_Annn(self: *Chip8) void {
    self.index = self.opcode & 0x0FFF;
}

/// Bnnn -> JP V0, addr: jump to location nnn + V0
fn OP_Bnnn(self: *Chip8) void {
    const addr: u16 = self.opcode & 0x0FFF;
    self.pc = self.registers[0x0] + addr;
}

/// Cxkk -> RND Vx, byte: set Vx = random byte AND kk
fn OP_Cxkk(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const byte: u8 = @intCast(self.opcode & 0x00FF);

    self.registers[Vx] = self.randByte() & byte;
}

/// helper function to compare two rl.Color values
fn colorEqual(a: rl.Color, b: rl.Color) bool {
    return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
}

/// Dxyn -> DRW Vx, Vy, nibble
/// display n-byte sprite from memory location I at (Vx, Vy), set VF = collision
fn OP_Dxyn(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const Vy: u8 = @intCast((self.opcode & 0x00F0) >> 4);
    const height: u8 = @intCast(self.opcode & 0x000F);
    const width: u8 = 8;

    // wrap if beyond screen boundaries
    const x_pos = self.registers[Vx] % DISPLAY_WIDTH;
    const y_pos = self.registers[Vy] % DISPLAY_HEIGHT;

    self.registers[0xF] = 0;

    for (0..height) |row| {
        const sprite_byte = self.memory[self.index + row];
        // make sure we don't go beyond the display buffer
        const index: u12 = @intCast(@min(
            ((y_pos + row) * DISPLAY_WIDTH) + x_pos,
            @as(u12, DISPLAY_WIDTH) * DISPLAY_HEIGHT - width - 1,
        ));
        const current = self.display[index .. index + width];

        for (0..width) |col| {
            const sprite_pixel = (sprite_byte & (@as(u8, 0x80) >> @intCast(col))) != 0;
            // check if current[col]
            const display_pixel = colorEqual(current[col], rl.Color.white);

            // if both pixels are on there is a collision
            if (sprite_pixel and display_pixel) {
                self.registers[0xF] = 1;
            }
            // xor display pixel with sprite pixel
            current[col] = if (display_pixel != sprite_pixel) rl.Color.white else rl.Color.black;
        }
    }
}

/// Ex9E -> SKP Vx: skip next instruction if key is pressed
fn OP_Ex9E(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const key = self.registers[Vx];

    if (self.keypad[key]) {
        self.pc += 2;
    }
}

/// ExA1 -> SKNP Vx: skip next instruction if key is not pressed
fn OP_ExA1(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const key = self.registers[Vx];

    if (!self.keypad[key]) {
        self.pc += 2;
    }
}

/// Fx07 -> LD Vx, DT: set Vx = delay timer value
fn OP_Fx07(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    self.registers[Vx] = self.delay_timer;
}

/// Fx0A -> LD Vx, K: wait for key press and store value of key in Vx
/// when no key is pressed the program waits by not moving the program counter
/// (self.pc -= 2)
fn OP_Fx0A(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);

    for (0..16) |key| {
        if (self.keypad[key]) {
            self.registers[Vx] = @intCast(key);
            return;
        }
    }

    // no key pressed, repeat this instruction
    self.pc -= 2;
}

/// Fx15 -> LD DT, Vx: set delay timer = Vx
fn OP_Fx15(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    self.delay_timer = self.registers[Vx];
}

/// Fx18 -> LD ST, Vx: set sound timer = Vx
fn OP_Fx18(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    self.sound_timer = self.registers[Vx];
}

/// Fx1E -> ADD I, Vx: set I = I + Vx
fn OP_Fx1E(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    self.index += @intCast(self.registers[Vx]);
}

/// Fx29 -> LD F, Vx: set I = location of sprite for digit at register Vx
fn OP_Fx29(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    // every digit is 5 bytes long
    self.index = FONTSET_START_ADDR + (self.registers[Vx] * 5);
}

/// Fx33 -> LD B, Vx: store BCD representation of Vx in memory locations I,
/// I+1, and I+2
/// Interpreter takes decimal value of Vx, and places hundreds digit in memory
/// at location in I, tens digit at I+1, and ones digit at I+2
fn OP_Fx33(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);

    var value = self.registers[Vx];
    self.memory[self.index + 2] = value % 10;

    value /= 10;
    self.memory[self.index + 1] = value % 10;

    value /= 10;
    self.memory[self.index] = value;
}

/// Fx55 -> LD [I], Vx: store registers V0 through Vx in memory starting at
/// location I
fn OP_Fx55(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);

    const start = self.index;
    const end = self.index + Vx + 1;
    std.mem.copyForwards(u8, self.memory[start..end], self.registers[0 .. Vx + 1]);
}

/// Fx65 -> LD Vx, [I]: read registers V0 through Vx from memory starting at
fn OP_Fx65(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);

    const start = self.index;
    const end = self.index + Vx + 1;
    std.mem.copyForwards(u8, self.registers[0 .. Vx + 1], self.memory[start..end]);
}

/// NOP: no operation (used for unknown opcodes)
fn NOP(self: *Chip8) void {
    _ = self;
}

// ============================================
// below are the test functions for the methods
// ============================================

test "initialize" {
    var chip8 = Chip8.init();

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

    // test if fontset is loaded into memory correctly
    try std.testing.expectEqualSlices(u8, &fontset, chip8.memory[0x50 .. 0x50 + fontset.len]);
}

test "load rom" {
    var chip8 = Chip8.init();

    // create a dummy rom file
    const rom_data: [10]u8 = .{ 0x00, 0xE0, 0xA2, 0x2A, 0x60, 0x0C, 0x61, 0x08, 0xD0, 0x18 };
    const rom_file_name = "test_rom.ch8";

    var rom_file = try std.fs.cwd().createFile(rom_file_name, .{ .truncate = true });
    defer rom_file.close();
    defer std.fs.cwd().deleteFile(rom_file_name) catch |err| {
        std.debug.print("Failed to remove {s}: {any}\n", .{ rom_file_name, err });
    };

    var buffer: [10]u8 = undefined;
    var file_writer = rom_file.writer(&buffer);
    const writer = &file_writer.interface;

    try writer.writeAll(&rom_data);
    try writer.flush();

    // load the rom into chip8 memory
    try chip8.loadRom(rom_file_name);

    // check if the rom data is loaded correctly into memory starting at 0x200
    try std.testing.expectEqualSlices(u8, &rom_data, chip8.memory[0x200 .. 0x200 + rom_data.len]);
}

test "clear display" {
    var chip8 = Chip8.init();

    const clean = chip8.display;

    @memset(chip8.display[0..3], true);
    @memset(chip8.display[5..20], true);
    @memset(chip8.display[100..120], true);
    @memset(chip8.display[250..300], true);
    @memset(chip8.display[400..500], true);

    chip8.OP_00E0();

    try std.testing.expectEqualSlices(bool, &clean, &chip8.display);
}

test "return from subroutine" {
    var chip8 = Chip8.init();

    chip8.sp = 6;
    chip8.stack[chip8.sp] = 5;
    chip8.sp += 1;
    chip8.pc = 10;

    chip8.OP_00EE();

    try std.testing.expectEqual(6, chip8.sp);
    try std.testing.expectEqual(5, chip8.pc);
}

test "jump to location" {
    var chip8 = Chip8.init();

    chip8.opcode = 0x13AF;
    chip8.OP_1nnn();

    try std.testing.expectEqual(0x3AF, chip8.pc);
}

test "call function" {
    var chip8 = Chip8.init();

    chip8.opcode = 0x27F7;
    var old_pc = chip8.pc;
    var old_sp = chip8.sp;
    chip8.OP_2nnn();

    try std.testing.expectEqual(0x7F7, chip8.pc);
    try std.testing.expectEqual(1, chip8.sp);
    try std.testing.expectEqual(old_pc, chip8.stack[old_sp]);

    chip8.opcode = 0x253A;
    old_pc = chip8.pc;
    old_sp = chip8.sp;
    chip8.OP_2nnn();

    try std.testing.expectEqual(0x53A, chip8.pc);
    try std.testing.expectEqual(2, chip8.sp);
    try std.testing.expectEqual(old_pc, chip8.stack[old_sp]);
}

test "SE Vx byte, Vx == kk" {
    var chip8 = Chip8.init();

    chip8.registers[0x0] = 0x45;
    chip8.opcode = 0x3045;

    chip8.OP_3xkk();

    try std.testing.expectEqual(0x200 + 2, chip8.pc);

    chip8.registers[0xB] = 0xFA;
    chip8.opcode = 0x3BFA;

    chip8.OP_3xkk();

    try std.testing.expectEqual(0x200 + 4, chip8.pc);
}

test "SE Vx byte, Vx != kk" {
    var chip8 = Chip8.init();

    chip8.registers[0x0] = 0x45;
    chip8.opcode = 0x303A;

    chip8.OP_3xkk();

    try std.testing.expectEqual(0x200, chip8.pc);
}

test "SNE Vx byte, Vx != kk" {
    var chip8 = Chip8.init();

    chip8.registers[0xE] = 0x11;
    chip8.opcode = 0x3E10;

    chip8.OP_4xkk();

    try std.testing.expectEqual(0x200 + 2, chip8.pc);

    chip8.registers[0x8] = 0x15;
    chip8.opcode = 0x3800;

    chip8.OP_4xkk();

    try std.testing.expectEqual(0x200 + 4, chip8.pc);
}

test "SNE Vx byte, Vx == kk" {
    var chip8 = Chip8.init();

    chip8.registers[0x3] = 0xA5;
    chip8.opcode = 0x33A5;

    chip8.OP_4xkk();

    try std.testing.expectEqual(0x200, chip8.pc);
}

test "SE Vx Vy, Vx == Vy" {
    var chip8 = Chip8.init();

    chip8.registers[0x5] = 0x55;
    chip8.registers[0x4] = 0x55;
    chip8.opcode = 0x5540;

    chip8.OP_5xy0();

    try std.testing.expectEqual(0x200 + 2, chip8.pc);

    chip8.registers[0x0] = 0x34;
    chip8.registers[0xA] = 0x34;
    chip8.opcode = 0x50A0;

    chip8.OP_5xy0();

    try std.testing.expectEqual(0x200 + 4, chip8.pc);
}

test "SE Vx Vy, Vx != Vy" {
    var chip8 = Chip8.init();

    chip8.registers[0x1] = 0xAA;
    chip8.registers[0xA] = 0xA0;
    chip8.opcode = 0x51A0;

    chip8.OP_5xy0();

    try std.testing.expectEqual(0x200, chip8.pc);
}

test "load byte into Vx" {
    var chip8 = Chip8.init();

    chip8.opcode = 0x6B3A;

    chip8.OP_6xkk();

    try std.testing.expectEqual(0x3A, chip8.registers[0xB]);
}

test "add byte to Vx" {
    var chip8 = Chip8.init();

    chip8.opcode = 0x7A34;
    chip8.OP_7xkk();

    try std.testing.expectEqual(0x34, chip8.registers[0xA]);

    chip8.opcode = 0x7A54;
    chip8.OP_7xkk();

    try std.testing.expectEqual(0x34 +% 0x54, chip8.registers[0xA]);
}

test "add byte to Vx with wrap" {
    var chip8 = Chip8.init();

    chip8.opcode = 0x7BFA;
    chip8.OP_7xkk();

    try std.testing.expectEqual(@as(u8, 0xFA), chip8.registers[0xB]);

    chip8.opcode = 0x7BAB;
    chip8.OP_7xkk();

    try std.testing.expectEqual(@as(u8, 0xFA) +% 0xAB, chip8.registers[0xB]);
}

test "load Vy into Vx" {
    var chip8 = Chip8.init();

    chip8.registers[0x2] = 0x34;
    chip8.opcode = 0x8280;

    try std.testing.expectEqual(0x34, chip8.registers[0x2]);

    chip8.registers[0x2] = 0xBA;
    chip8.opcode = 0x8280;

    try std.testing.expectEqual(0xBA, chip8.registers[0x2]);
}

test "OR Vx Vy" {
    var chip8 = Chip8.init();

    const fst = 0b00110111;
    const snd = 0b10100011;

    chip8.registers[0x5] = fst;
    chip8.registers[0x8] = snd;
    chip8.opcode = 0x8581;

    chip8.OP_8xy1();

    try std.testing.expectEqual(fst | snd, chip8.registers[0x5]);
}

test "AND Vx Vy" {
    var chip8 = Chip8.init();

    const fst = 0b11001011;
    const snd = 0b01001110;

    chip8.registers[0xC] = fst;
    chip8.registers[0x9] = snd;
    chip8.opcode = 0x8C92;

    chip8.OP_8xy2();

    try std.testing.expectEqual(fst & snd, chip8.registers[0xC]);
}

test "XOR Vx Vy" {
    var chip8 = Chip8.init();

    const fst = 0b10100110;
    const snd = 0b01110010;

    chip8.registers[0x8] = fst;
    chip8.registers[0xD] = snd;
    chip8.opcode = 0x88D3;

    chip8.OP_8xy3();

    try std.testing.expectEqual(fst ^ snd, chip8.registers[0x8]);
}

test "ADD Vx Vy with carry" {
    var chip8 = Chip8.init();

    const fst: u8 = 0x34;
    const snd: u8 = 0x65;

    chip8.registers[0x5] = fst;
    chip8.registers[0x8] = snd;
    chip8.opcode = 0x8584;

    chip8.OP_8xy4();

    try std.testing.expectEqual(fst +% snd, chip8.registers[0x5]);
    try std.testing.expectEqual(0, chip8.registers[0xF]);
}

test "ADD Vx Vy with carry with overflow" {
    var chip8 = Chip8.init();

    const fst: u8 = 0xF8;
    const snd: u8 = 0x3A;

    chip8.registers[0xC] = fst;
    chip8.registers[0xA] = snd;
    chip8.opcode = 0x8CA4;

    chip8.OP_8xy4();

    try std.testing.expectEqual(fst +% snd, chip8.registers[0xC]);
    try std.testing.expectEqual(1, chip8.registers[0xF]);
}

test "SUB Vx Vy" {
    var chip8 = Chip8.init();

    const fst: u8 = 0x34;
    const snd: u8 = 0x30;

    chip8.registers[0x4] = fst;
    chip8.registers[0x7] = snd;
    chip8.opcode = 0x8475;

    chip8.OP_8xy5();

    try std.testing.expectEqual(fst -% snd, chip8.registers[0x4]);
    try std.testing.expectEqual(0, chip8.registers[0xF]);
}

test "SUB Vx Vy with overflow" {
    var chip8 = Chip8.init();

    const fst: u8 = 0x30;
    const snd: u8 = 0x34;

    chip8.registers[0x8] = fst;
    chip8.registers[0x0] = snd;
    chip8.opcode = 0x8805;

    chip8.OP_8xy5();

    try std.testing.expectEqual(fst -% snd, chip8.registers[0x8]);
    try std.testing.expectEqual(1, chip8.registers[0xF]);
}

test "shift right Vx" {
    var chip8 = Chip8.init();

    const num: u8 = 16;

    chip8.registers[0x3] = num;
    chip8.opcode = 0x8306;

    chip8.OP_8xy6();

    try std.testing.expectEqual(num >> 1, chip8.registers[0x3]);
    try std.testing.expectEqual(0, chip8.registers[0xF]);
}

test "shift right Vx with overflow" {
    var chip8 = Chip8.init();

    const num: u8 = 15;

    chip8.registers[0xA] = num;
    chip8.opcode = 0x8A06;

    chip8.OP_8xy6();

    try std.testing.expectEqual(num >> 1, chip8.registers[0xA]);
    try std.testing.expectEqual(1, chip8.registers[0xF]);
}

test "SUBN Vx Vy" {
    var chip8 = Chip8.init();

    const fst: u8 = 0x34;
    const snd: u8 = 0x30;

    chip8.registers[0x4] = snd;
    chip8.registers[0x7] = fst;
    chip8.opcode = 0x8475;

    chip8.OP_8xy7();

    try std.testing.expectEqual(fst -% snd, chip8.registers[0x4]);
    try std.testing.expectEqual(0, chip8.registers[0xF]);
}

test "SUBN Vx Vy with overflow" {
    var chip8 = Chip8.init();

    const fst: u8 = 0x30;
    const snd: u8 = 0x34;

    chip8.registers[0x8] = snd;
    chip8.registers[0x0] = fst;
    chip8.opcode = 0x8805;

    chip8.OP_8xy7();

    try std.testing.expectEqual(fst -% snd, chip8.registers[0x8]);
    try std.testing.expectEqual(1, chip8.registers[0xF]);
}

test "shift left Vx" {
    var chip8 = Chip8.init();

    const num: u8 = 16;

    chip8.registers[0x3] = num;
    chip8.opcode = 0x8306;

    chip8.OP_8xyE();

    try std.testing.expectEqual(num << 1, chip8.registers[0x3]);
    try std.testing.expectEqual(0, chip8.registers[0xF]);
}

test "shift left Vx with overflow" {
    var chip8 = Chip8.init();

    const num: u8 = 200;

    chip8.registers[0xA] = num;
    chip8.opcode = 0x8A06;

    chip8.OP_8xyE();

    try std.testing.expectEqual(num << 1, chip8.registers[0xA]);
    try std.testing.expectEqual(1, chip8.registers[0xF]);
}

test "SNE Vx Vy, Vx != Vy" {
    var chip8 = Chip8.init();

    chip8.registers[0xE] = 0x11;
    chip8.registers[0xD] = 0x13;
    chip8.opcode = 0x9ED0;

    chip8.OP_9xy0();

    try std.testing.expectEqual(0x200 + 2, chip8.pc);

    chip8.registers[0x8] = 0x15;
    chip8.registers[0xA] = 0x13;
    chip8.opcode = 0x98A0;

    chip8.OP_9xy0();

    try std.testing.expectEqual(0x200 + 4, chip8.pc);
}

test "SNE Vx Vy, Vx == Vy" {
    var chip8 = Chip8.init();

    chip8.registers[0x3] = 0xA5;
    chip8.registers[0x4] = 0xA5;
    chip8.opcode = 0x9340;

    chip8.OP_9xy0();

    try std.testing.expectEqual(0x200, chip8.pc);
}

test "load address into index" {
    var chip8 = Chip8.init();

    chip8.opcode = 0xAF87;

    chip8.OP_Annn();

    try std.testing.expectEqual(0xF87, chip8.index);
}

test "jump to address + V0" {
    var chip8 = Chip8.init();

    chip8.registers[0x0] = 0x87;
    chip8.opcode = 0xB34F;

    chip8.OP_Bnnn();

    try std.testing.expectEqual(0x87 + 0x34F, chip8.pc);
}

test "drawing to display" {
    var chip8 = Chip8.init();

    // select character to draw (E)
    chip8.opcode = 0xA096;
    chip8.OP_Annn();

    // how E should be displayed
    const E = [5][8]bool{
        .{ true, true, true, true, false, false, false, false },
        .{ true, false, false, false, false, false, false, false },
        .{ true, true, true, true, false, false, false, false },
        .{ true, false, false, false, false, false, false, false },
        .{ true, true, true, true, false, false, false, false },
    };

    // set coordinates
    chip8.registers[0x2] = 2;
    chip8.registers[0x3] = 3;

    // perform draw
    chip8.opcode = 0xD235;
    chip8.OP_Dxyn();

    var first: u12 = 3 * 64 + 2;
    try std.testing.expectEqualSlices(bool, &E[0], chip8.display[first .. first + 8]);
    first = 4 * 64 + 2;
    try std.testing.expectEqualSlices(bool, &E[1], chip8.display[first .. first + 8]);
    first = 5 * 64 + 2;
    try std.testing.expectEqualSlices(bool, &E[2], chip8.display[first .. first + 8]);
    first = 6 * 64 + 2;
    try std.testing.expectEqualSlices(bool, &E[3], chip8.display[first .. first + 8]);
    first = 7 * 64 + 2;
    try std.testing.expectEqualSlices(bool, &E[4], chip8.display[first .. first + 8]);
    try std.testing.expectEqual(0, chip8.registers[0xF]);

    // select next character to draw (F)
    chip8.opcode = 0xA09B;
    chip8.OP_Annn();

    // how E xor F should be displayed
    const ExorF = [5][8]bool{
        .{ false, false, false, false, false, false, false, false },
        .{ false, false, false, false, false, false, false, false },
        .{ false, false, false, false, false, false, false, false },
        .{ false, false, false, false, false, false, false, false },
        .{ false, true, true, true, false, false, false, false },
    };

    // perform draw
    chip8.opcode = 0xD235;
    chip8.OP_Dxyn();

    first = 3 * 64 + 2;
    try std.testing.expectEqualSlices(bool, &ExorF[0], chip8.display[first .. first + 8]);
    first = 4 * 64 + 2;
    try std.testing.expectEqualSlices(bool, &ExorF[1], chip8.display[first .. first + 8]);
    first = 5 * 64 + 2;
    try std.testing.expectEqualSlices(bool, &ExorF[2], chip8.display[first .. first + 8]);
    first = 6 * 64 + 2;
    try std.testing.expectEqualSlices(bool, &ExorF[3], chip8.display[first .. first + 8]);
    first = 7 * 64 + 2;
    try std.testing.expectEqualSlices(bool, &ExorF[4], chip8.display[first .. first + 8]);
    try std.testing.expectEqual(1, chip8.registers[0xF]);
}

test "skip if key pressed" {
    var chip8 = Chip8.init();

    chip8.registers[0x1] = 0x5;
    chip8.keypad[0x5] = true;
    chip8.opcode = 0xE19E;

    chip8.OP_Ex9E();

    try std.testing.expectEqual(0x200 + 2, chip8.pc);

    chip8.registers[0x2] = 0xA;
    chip8.opcode = 0xE29E;

    chip8.OP_Ex9E();

    try std.testing.expectEqual(0x200 + 2, chip8.pc);
}

test "skip if key not pressed" {
    var chip8 = Chip8.init();

    chip8.registers[0x1] = 0x5;
    chip8.keypad[0x5] = false;
    chip8.opcode = 0xE1A1;

    chip8.OP_ExA1();

    try std.testing.expectEqual(0x200 + 2, chip8.pc);

    chip8.registers[0x2] = 0xA;
    chip8.keypad[0xA] = true;
    chip8.opcode = 0xE2A1;

    chip8.OP_ExA1();

    try std.testing.expectEqual(0x200 + 2, chip8.pc);
}

test "set Vx = delay timer" {
    var chip8 = Chip8.init();

    chip8.delay_timer = 55;
    chip8.opcode = 0xF107;

    chip8.OP_Fx07();

    try std.testing.expectEqual(55, chip8.registers[0x1]);
}

test "wait for key press and store in Vx" {
    var chip8 = Chip8.init();

    chip8.opcode = 0xF30A;
    chip8.pc += 2;

    // no key pressed, pc should remain the same after calling LD_Vx_K
    chip8.OP_Fx0A();
    try std.testing.expectEqual(0x0, chip8.registers[0x3]);
    try std.testing.expectEqual(0x200, chip8.pc);

    // simulate key press
    chip8.keypad[0x7] = true;
    chip8.pc += 2;

    chip8.OP_Fx0A();
    try std.testing.expectEqual(0x7, chip8.registers[0x3]);
    try std.testing.expectEqual(0x200 + 2, chip8.pc);
}

test "set delay timer = Vx" {
    var chip8 = Chip8.init();

    chip8.registers[0x4] = 120;
    chip8.opcode = 0xF415;

    chip8.OP_Fx15();

    try std.testing.expectEqual(120, chip8.delay_timer);
}

test "set sound timer = Vx" {
    var chip8 = Chip8.init();

    chip8.registers[0x9] = 200;
    chip8.opcode = 0xF918;

    chip8.OP_Fx18();

    try std.testing.expectEqual(200, chip8.sound_timer);
}

test "add Vx to I" {
    var chip8 = Chip8.init();

    chip8.index = 0x300;
    chip8.registers[0x2] = 0x50;
    chip8.opcode = 0xF21E;

    chip8.OP_Fx1E();

    try std.testing.expectEqual(0x350, chip8.index);
}

test "set I to location of sprite for digit in Vx" {
    var chip8 = Chip8.init();

    chip8.registers[0x3] = 0xA; // digit A
    chip8.opcode = 0xF329;

    chip8.OP_Fx29();

    try std.testing.expectEqual(FONTSET_START_ADDR + (0xA * 5), chip8.index);

    chip8.registers[0x7] = 0x4; // digit 4
    chip8.opcode = 0xF729;

    chip8.OP_Fx29();

    try std.testing.expectEqual(FONTSET_START_ADDR + (0x4 * 5), chip8.index);
}

test "store BCD representation of Vx in memory" {
    var chip8 = Chip8.init();

    chip8.registers[0x5] = 234;
    chip8.index = 0x300;
    chip8.opcode = 0xF533;

    chip8.OP_Fx33();

    try std.testing.expectEqual(2, chip8.memory[0x300]);
    try std.testing.expectEqual(3, chip8.memory[0x301]);
    try std.testing.expectEqual(4, chip8.memory[0x302]);

    chip8.registers[0xA] = 57;
    chip8.index = 0x400;
    chip8.opcode = 0xFA33;

    chip8.OP_Fx33();

    try std.testing.expectEqual(0, chip8.memory[0x400]);
    try std.testing.expectEqual(5, chip8.memory[0x401]);
    try std.testing.expectEqual(7, chip8.memory[0x402]);
}

test "store registers V0 through Vx in memory starting at I" {
    var chip8 = Chip8.init();

    chip8.registers[0x0] = 0x12;
    chip8.registers[0x1] = 0x34;
    chip8.registers[0x2] = 0x56;
    chip8.registers[0x3] = 0x78;
    chip8.registers[0x4] = 0x9A;

    chip8.index = 0x300;
    chip8.opcode = 0xF455; // store V0 through V4

    chip8.OP_Fx55();

    try std.testing.expectEqual(0x12, chip8.memory[0x300]);
    try std.testing.expectEqual(0x34, chip8.memory[0x301]);
    try std.testing.expectEqual(0x56, chip8.memory[0x302]);
    try std.testing.expectEqual(0x78, chip8.memory[0x303]);
    try std.testing.expectEqual(0x9A, chip8.memory[0x304]);
}

test "read registers V0 through Vx from memory starting at I" {
    var chip8 = Chip8.init();

    chip8.memory[0x400] = 0xAB;
    chip8.memory[0x401] = 0xCD;
    chip8.memory[0x402] = 0xEF;
    chip8.memory[0x403] = 0x12;
    chip8.memory[0x404] = 0x34;

    chip8.index = 0x400;
    chip8.opcode = 0xF465; // read into V0 through V4

    chip8.OP_Fx65();

    try std.testing.expectEqual(0xAB, chip8.registers[0x0]);
    try std.testing.expectEqual(0xCD, chip8.registers[0x1]);
    try std.testing.expectEqual(0xEF, chip8.registers[0x2]);
    try std.testing.expectEqual(0x12, chip8.registers[0x3]);
    try std.testing.expectEqual(0x34, chip8.registers[0x4]);
}
