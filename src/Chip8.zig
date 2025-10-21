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
display: [64 * 32]bool = @splat(false),
VIDEO_WIDTH: u8 = 64,
VIDEO_HEIGHT: u8 = 32,
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

/// generate a random u8 integer
fn randByte(self: *const Chip8) u8 {
    return self.rand.int(u8);
}

// ====================================
// below are the 34 opcode instructions
// ====================================

/// 00E0 -> CLS: clear display
fn CLS(self: *Chip8) void {
    self.display = @splat(false);
}

/// 00EE -> RET: return from subroutine
fn RET(self: *Chip8) void {
    self.sp -= 1;
    self.pc = self.stack[self.sp];
}

/// 1nnn -> JP addr: jump to location nnn
fn JP_addr(self: *Chip8) void {
    const addr: u16 = self.opcode & 0x0FFF;
    self.pc = addr;
}

/// 2nnn -> CALL addr: call subroutine at nnn
fn CALL_addr(self: *Chip8) void {
    const addr: u16 = self.opcode & 0x0FFF;
    self.stack[self.sp] = self.pc;
    self.sp += 1;
    self.pc = addr;
}

/// 3xkk -> SE Vx, byte: skip next instruction if Vx == kk
fn SE_Vx_byte(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const byte: u8 = @intCast(self.opcode & 0x00FF);

    if (self.registers[Vx] == byte) {
        self.pc += 2;
    }
}

/// 4xkk -> SNE Vx, byte: skip next instruction if Vx != kk
fn SNE_Vx_byte(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const byte: u8 = @intCast(self.opcode & 0x00FF);

    if (self.registers[Vx] != byte) {
        self.pc += 2;
    }
}

/// 5xy0 -> SE Vx, Vy: skip net instruction if Vx == Vy
fn SE_Vx_Vy(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const Vy: u8 = @intCast((self.opcode & 0x00F0) >> 4);

    if (self.registers[Vx] == self.registers[Vy]) {
        self.pc += 2;
    }
}

/// 6xkk -> LD Vx, byte: set Vx = kk
fn LD_Vx_byte(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const byte: u8 = @intCast(self.opcode & 0x00FF);

    self.registers[Vx] = byte;
}

/// 7xkk -> ADD Vx, byte: set Vx = kk
fn ADD_Vx_byte(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);

    // +% wraps when overflow
    self.registers[Vx] +%= @intCast(self.opcode & 0x00FF);
}

/// 8xy0 -> LD Vx, Vy: set Vx = Vy
fn LD_Vx_Vy(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const Vy: u8 = @intCast((self.opcode & 0x00F0) >> 4);

    self.registers[Vx] = self.registers[Vy];
}

/// 8xy1 -> OR Vx, Vy: set Vx = Vx OR Vy
fn OR_Vx_Vy(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const Vy: u8 = @intCast((self.opcode & 0x00F0) >> 4);

    self.registers[Vx] |= self.registers[Vy];
}

/// 8xy2 -> AND Vx, Vy: set Vx = Vx AND Vy
fn AND_Vx_Vy(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const Vy: u8 = @intCast((self.opcode & 0x00F0) >> 4);

    self.registers[Vx] &= self.registers[Vy];
}

/// 8xy3 -> XOR Vx, Vy: set Vx = Vx XOR Vy
fn XOR_Vx_Vy(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const Vy: u8 = @intCast((self.opcode & 0x00F0) >> 4);

    self.registers[Vx] ^= self.registers[Vy];
}

/// 8xy4 -> ADD Vx, Vy: set Vx = Vx + Vy, set VF = carry
/// add with overflow. VF is set to 1 if result greater than 8 bits
fn ADD_Vx_Vy(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const Vy: u8 = @intCast((self.opcode & 0x00F0) >> 4);

    self.registers[Vx], self.registers[0xF] = @addWithOverflow(self.registers[Vx], self.registers[Vy]);
}

/// 8xy5 -> SUB VX, Vy: set Vx = Vx - Vy, set VF = NOT borrow
/// sub with overflow. if Vx > Vy, then VF is set to 1, otherwise 0
fn SUB_Vx_Vy(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const Vy: u8 = @intCast((self.opcode & 0x00F0) >> 4);

    self.registers[Vx], self.registers[0xF] = @subWithOverflow(self.registers[Vx], self.registers[Vy]);
}

/// 8xy6 -> SHR Vx: set Vx = Vx SHR 1
/// right shift (div by 2) with overflow of least significant bit
fn SHR_Vx(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);

    self.registers[0xF] = self.registers[Vx] & 0x1;
    self.registers[Vx] >>= 1;
}

/// 8xy7 -> SUBN Vx, Vy: set Vx = Vy - Vx, set VF = NOT borrow
/// sub with overflow. if Vy > Vx, then VF is set to 1, otherwise 0
fn SUBN_Vx_Vy(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const Vy: u8 = @intCast((self.opcode & 0x00F0) >> 4);

    self.registers[Vx], self.registers[0xF] = @subWithOverflow(self.registers[Vy], self.registers[Vx]);
}

/// 8xyE -> SHL Vx: set Vx = Vx SHL 1
/// left shift (mult by 2) with overflow
fn SHL_Vx(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);

    self.registers[Vx], self.registers[0xF] = @shlWithOverflow(self.registers[Vx], 1);
}

/// 9xy0 -> SNE Vx, Vy: skip next instruction if Vx != Vy
fn SNE_Vx_Vy(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const Vy: u8 = @intCast((self.opcode & 0x00F0) >> 4);

    if (self.registers[Vx] != self.registers[Vy]) {
        self.pc += 2;
    }
}

/// Annn -> LD I, addr: set I = nnn
fn LD_I_addr(self: *Chip8) void {
    self.index = self.opcode & 0x0FFF;
}

/// Bnnn -> JP V0, addr: jump to location nnn + V0
fn JP_V0_addr(self: *Chip8) void {
    const addr: u16 = self.opcode & 0x0FFF;
    self.pc = self.registers[0x0] + addr;
}

/// Cxkk -> RND Vx, byte: set Vx = random byte AND kk
fn RND_Vx_byte(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const byte: u8 = @intCast(self.opcode & 0x00FF);

    self.registers[Vx] = self.randByte() & byte;
}

/// Dxyn -> DRW Vx, Vy, nibble
/// display n-byte sprite from memory location I at (Vx, Vy), set VF = collision
fn DRW_Vx_Vy_n(self: *Chip8) void {
    const Vx: u8 = @intCast((self.opcode & 0x0F00) >> 8);
    const Vy: u8 = @intCast((self.opcode & 0x00F0) >> 4);
    const height: u8 = @intCast(self.opcode & 0x000F);
    const width: u8 = 8;

    // wrap if beyond screen boundaries
    const x_pos = self.registers[Vx] % self.VIDEO_WIDTH;
    const y_pos = self.registers[Vy] % self.VIDEO_HEIGHT;

    self.registers[0xF] = 0;

    for (0..height) |row| {
        const sprite_byte = self.memory[self.index + row];
        const index: u12 = @intCast(((y_pos + row) * self.VIDEO_WIDTH) + x_pos);
        const current = self.display[index .. index + width];

        for (0..width) |col| {
            const sprite_pixel = (sprite_byte & (@as(u8, 0x80) >> @intCast(col))) != 0;
            const display_pixel = current[col];

            // if both pixels are on there is a collision
            if (sprite_pixel and display_pixel) {
                self.registers[0xF] = 1;
            }
            // xor display pixel with sprite pixel
            current[col] = display_pixel != sprite_pixel;
        }
    }
}

// ============================================
// below are the test functions for the methods
// ============================================

test "clear display" {
    var chip8 = Chip8.init();

    const clean = chip8.display;

    @memset(chip8.display[0..3], true);
    @memset(chip8.display[5..20], true);
    @memset(chip8.display[100..120], true);
    @memset(chip8.display[250..300], true);
    @memset(chip8.display[400..500], true);

    chip8.CLS();

    try std.testing.expectEqualSlices(bool, &clean, &chip8.display);
}

test "return from subroutine" {
    var chip8 = Chip8.init();

    chip8.sp = 6;
    chip8.stack[chip8.sp] = 5;
    chip8.sp += 1;
    chip8.pc = 10;

    chip8.RET();

    try std.testing.expectEqual(6, chip8.sp);
    try std.testing.expectEqual(5, chip8.pc);
}

test "jump to location" {
    var chip8 = Chip8.init();

    chip8.opcode = 0x13AF;
    chip8.JP_addr();

    try std.testing.expectEqual(0x3AF, chip8.pc);
}

test "call function" {
    var chip8 = Chip8.init();

    chip8.opcode = 0x27F7;
    var old_pc = chip8.pc;
    var old_sp = chip8.sp;
    chip8.CALL_addr();

    try std.testing.expectEqual(0x7F7, chip8.pc);
    try std.testing.expectEqual(1, chip8.sp);
    try std.testing.expectEqual(old_pc, chip8.stack[old_sp]);

    chip8.opcode = 0x253A;
    old_pc = chip8.pc;
    old_sp = chip8.sp;
    chip8.CALL_addr();

    try std.testing.expectEqual(0x53A, chip8.pc);
    try std.testing.expectEqual(2, chip8.sp);
    try std.testing.expectEqual(old_pc, chip8.stack[old_sp]);
}

test "SE Vx byte, Vx == kk" {
    var chip8 = Chip8.init();

    chip8.registers[0x0] = 0x45;
    chip8.opcode = 0x3045;

    chip8.SE_Vx_byte();

    try std.testing.expectEqual(0x200 + 2, chip8.pc);

    chip8.registers[0xB] = 0xFA;
    chip8.opcode = 0x3BFA;

    chip8.SE_Vx_byte();

    try std.testing.expectEqual(0x200 + 4, chip8.pc);
}

test "SE Vx byte, Vx != kk" {
    var chip8 = Chip8.init();

    chip8.registers[0x0] = 0x45;
    chip8.opcode = 0x303A;

    chip8.SE_Vx_byte();

    try std.testing.expectEqual(0x200, chip8.pc);
}

test "SNE Vx byte, Vx != kk" {
    var chip8 = Chip8.init();

    chip8.registers[0xE] = 0x11;
    chip8.opcode = 0x3E10;

    chip8.SNE_Vx_byte();

    try std.testing.expectEqual(0x200 + 2, chip8.pc);

    chip8.registers[0x8] = 0x15;
    chip8.opcode = 0x3800;

    chip8.SNE_Vx_byte();

    try std.testing.expectEqual(0x200 + 4, chip8.pc);
}

test "SNE Vx byte, Vx == kk" {
    var chip8 = Chip8.init();

    chip8.registers[0x3] = 0xA5;
    chip8.opcode = 0x33A5;

    chip8.SNE_Vx_byte();

    try std.testing.expectEqual(0x200, chip8.pc);
}

test "SE Vx Vy, Vx == Vy" {
    var chip8 = Chip8.init();

    chip8.registers[0x5] = 0x55;
    chip8.registers[0x4] = 0x55;
    chip8.opcode = 0x5540;

    chip8.SE_Vx_Vy();

    try std.testing.expectEqual(0x200 + 2, chip8.pc);

    chip8.registers[0x0] = 0x34;
    chip8.registers[0xA] = 0x34;
    chip8.opcode = 0x50A0;

    chip8.SE_Vx_Vy();

    try std.testing.expectEqual(0x200 + 4, chip8.pc);
}

test "SE Vx Vy, Vx != Vy" {
    var chip8 = Chip8.init();

    chip8.registers[0x1] = 0xAA;
    chip8.registers[0xA] = 0xA0;
    chip8.opcode = 0x51A0;

    chip8.SE_Vx_Vy();

    try std.testing.expectEqual(0x200, chip8.pc);
}

test "load byte into Vx" {
    var chip8 = Chip8.init();

    chip8.opcode = 0x6B3A;

    chip8.LD_Vx_byte();

    try std.testing.expectEqual(0x3A, chip8.registers[0xB]);
}

test "add byte to Vx" {
    var chip8 = Chip8.init();

    chip8.opcode = 0x7A34;
    chip8.ADD_Vx_byte();

    try std.testing.expectEqual(0x34, chip8.registers[0xA]);

    chip8.opcode = 0x7A54;
    chip8.ADD_Vx_byte();

    try std.testing.expectEqual(0x34 +% 0x54, chip8.registers[0xA]);
}

test "add byte to Vx with wrap" {
    var chip8 = Chip8.init();

    chip8.opcode = 0x7BFA;
    chip8.ADD_Vx_byte();

    try std.testing.expectEqual(@as(u8, 0xFA), chip8.registers[0xB]);

    chip8.opcode = 0x7BAB;
    chip8.ADD_Vx_byte();

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

    chip8.OR_Vx_Vy();

    try std.testing.expectEqual(fst | snd, chip8.registers[0x5]);
}

test "AND Vx Vy" {
    var chip8 = Chip8.init();

    const fst = 0b11001011;
    const snd = 0b01001110;

    chip8.registers[0xC] = fst;
    chip8.registers[0x9] = snd;
    chip8.opcode = 0x8C92;

    chip8.AND_Vx_Vy();

    try std.testing.expectEqual(fst & snd, chip8.registers[0xC]);
}

test "XOR Vx Vy" {
    var chip8 = Chip8.init();

    const fst = 0b10100110;
    const snd = 0b01110010;

    chip8.registers[0x8] = fst;
    chip8.registers[0xD] = snd;
    chip8.opcode = 0x88D3;

    chip8.XOR_Vx_Vy();

    try std.testing.expectEqual(fst ^ snd, chip8.registers[0x8]);
}

test "ADD Vx Vy with carry" {
    var chip8 = Chip8.init();

    const fst: u8 = 0x34;
    const snd: u8 = 0x65;

    chip8.registers[0x5] = fst;
    chip8.registers[0x8] = snd;
    chip8.opcode = 0x8584;

    chip8.ADD_Vx_Vy();

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

    chip8.ADD_Vx_Vy();

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

    chip8.SUB_Vx_Vy();

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

    chip8.SUB_Vx_Vy();

    try std.testing.expectEqual(fst -% snd, chip8.registers[0x8]);
    try std.testing.expectEqual(1, chip8.registers[0xF]);
}

test "shift right Vx" {
    var chip8 = Chip8.init();

    const num: u8 = 16;

    chip8.registers[0x3] = num;
    chip8.opcode = 0x8306;

    chip8.SHR_Vx();

    try std.testing.expectEqual(num >> 1, chip8.registers[0x3]);
    try std.testing.expectEqual(0, chip8.registers[0xF]);
}

test "shift right Vx with overflow" {
    var chip8 = Chip8.init();

    const num: u8 = 15;

    chip8.registers[0xA] = num;
    chip8.opcode = 0x8A06;

    chip8.SHR_Vx();

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

    chip8.SUBN_Vx_Vy();

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

    chip8.SUBN_Vx_Vy();

    try std.testing.expectEqual(fst -% snd, chip8.registers[0x8]);
    try std.testing.expectEqual(1, chip8.registers[0xF]);
}

test "shift left Vx" {
    var chip8 = Chip8.init();

    const num: u8 = 16;

    chip8.registers[0x3] = num;
    chip8.opcode = 0x8306;

    chip8.SHL_Vx();

    try std.testing.expectEqual(num << 1, chip8.registers[0x3]);
    try std.testing.expectEqual(0, chip8.registers[0xF]);
}

test "shift left Vx with overflow" {
    var chip8 = Chip8.init();

    const num: u8 = 200;

    chip8.registers[0xA] = num;
    chip8.opcode = 0x8A06;

    chip8.SHL_Vx();

    try std.testing.expectEqual(num << 1, chip8.registers[0xA]);
    try std.testing.expectEqual(1, chip8.registers[0xF]);
}

test "SNE Vx Vy, Vx != Vy" {
    var chip8 = Chip8.init();

    chip8.registers[0xE] = 0x11;
    chip8.registers[0xD] = 0x13;
    chip8.opcode = 0x9ED0;

    chip8.SNE_Vx_Vy();

    try std.testing.expectEqual(0x200 + 2, chip8.pc);

    chip8.registers[0x8] = 0x15;
    chip8.registers[0xA] = 0x13;
    chip8.opcode = 0x98A0;

    chip8.SNE_Vx_Vy();

    try std.testing.expectEqual(0x200 + 4, chip8.pc);
}

test "SNE Vx Vy, Vx == Vy" {
    var chip8 = Chip8.init();

    chip8.registers[0x3] = 0xA5;
    chip8.registers[0x4] = 0xA5;
    chip8.opcode = 0x9340;

    chip8.SNE_Vx_Vy();

    try std.testing.expectEqual(0x200, chip8.pc);
}

test "load address into index" {
    var chip8 = Chip8.init();

    chip8.opcode = 0xAF87;

    chip8.LD_I_addr();

    try std.testing.expectEqual(0xF87, chip8.index);
}

test "jump to address + V0" {
    var chip8 = Chip8.init();

    chip8.registers[0x0] = 0x87;
    chip8.opcode = 0xB34F;

    chip8.JP_V0_addr();

    try std.testing.expectEqual(0x87 + 0x34F, chip8.pc);
}

// /// Dxyn -> DRW Vx, Vy, nibble
// /// display n-byte sprite from memory location I at (Vx, Vy), set VF = collision
// fn DRW_Vx_Vy_n(self: *Chip8) void {
//     const Vx: u8 = (self.opcode & 0x0F00) >> 8;
//     const Vy: u8 = (self.opcode & 0x00F0) >> 4;
//     const height: u8 = self.opcode & 0x000F;
//     const width: u8 = 8;
//
//     // wrap if beyond screen boundaries
//     const x_pos = self.registers[Vx] % self.VIDEO_WIDTH;
//     const y_pos = self.registers[Vy] % self.VIDEO_HEIGHT;
//
//     self.registers[0xF] = 0;
//
//     for (0..height) |row| {
//         const sprite_byte = self.memory[self.index + row];
//         const current = self.display[(y_pos * self.VIDEO_WIDTH) + x_pos .. x_pos + width];
//
//         for (0..width) |col| {
//             const sprite_pixel = (sprite_byte & (0x80 >> col)) != 0;
//             const display_pixel = &current[col];
//
//             // if both pixels are on there is a collision
//             self.registers[0xF] = sprite_pixel and display_pixel;
//             // xor display pixel with sprite pixel
//             display_pixel = !(display_pixel and true) and (display_pixel or true);
//         }
//     }
// }

// const fontset: [80]u8 = .{
//     0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
//     0x20, 0x60, 0x20, 0x20, 0x70, // 1
//     0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
//     0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
//     0x90, 0x90, 0xF0, 0x10, 0x10, // 4
//     0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
//     0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
//     0xF0, 0x10, 0x20, 0x40, 0x40, // 7
//     0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
//     0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
//     0xF0, 0x90, 0xF0, 0x90, 0x90, // A
//     0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
//     0xF0, 0x80, 0x80, 0x80, 0xF0, // C
//     0xE0, 0x90, 0x90, 0x90, 0xE0, // D
//     0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
//     0xF0, 0x80, 0xF0, 0x80, 0x80, // F
// };

test "drawing to display" {
    var chip8 = Chip8.init();

    // select character to draw (E)
    chip8.opcode = 0xA096;
    chip8.LD_I_addr();

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
    chip8.DRW_Vx_Vy_n();

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
    chip8.LD_I_addr();

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
    chip8.DRW_Vx_Vy_n();

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
