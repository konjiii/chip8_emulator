const Audio = @This();

const std = @import("std");
const rl = @import("raylib");

// Audio configuration
const SAMPLE_RATE: u32 = 44100;
const SAMPLE_SIZE: u32 = 32;
const CHANNELS: u32 = 1;
const BUFFER_SIZE: u32 = 1024;
// wave configuration
const WAVE_FREQUENCY: f32 = 440.0;
const WAVE_AMPLITUDE: f32 = 0.25;

is_playing: bool = false,

stream: rl.AudioStream = undefined,

// Golbal state
var current_amplitude: f32 = WAVE_AMPLITUDE;
var sample_counter: u32 = 0;
const samples_per_half_period: u32 = SAMPLE_RATE / @as(u32, @intFromFloat(WAVE_FREQUENCY)) / 2;

pub fn init() Audio {
    var audio = Audio{};

    rl.initAudioDevice();
    audio.stream = rl.loadAudioStream(SAMPLE_RATE, SAMPLE_SIZE, CHANNELS) catch |err| {
        std.debug.print("Failed to load audio stream: {}\n", .{err});
        @panic("Audio stream initialization failed");
    };

    rl.setAudioStreamCallback(audio.stream, audioCallback);

    return audio;
}

pub fn deinit(self: *Audio) void {
    rl.unloadAudioStream(self.stream);
    rl.closeAudioDevice();
}

/// callback function to generate audio samples for raylib
/// callconv(.c) is required for raylib to call this function correctly
fn audioCallback(buffer_data: ?*anyopaque, frames: c_uint) callconv(.c) void {
    // convert c pointer to zig pointer
    const buffer: [*]f32 = @ptrCast(@alignCast(buffer_data));

    // wave generation logic
    for (0..frames) |i| {
        buffer[i] = current_amplitude;
        sample_counter += 1;

        if (sample_counter >= samples_per_half_period) {
            current_amplitude = -current_amplitude;
            sample_counter = 0;
        }
    }
}

pub fn play(self: *Audio) void {
    if (!self.is_playing) {
        rl.playAudioStream(self.stream);
        self.is_playing = true;
    }
}

pub fn stop(self: *Audio) void {
    if (self.is_playing) {
        rl.stopAudioStream(self.stream);
        self.is_playing = false;
    }
}
