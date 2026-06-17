// TODO: not thread-safe; needs a lock once interrupts/SMP land
const std = @import("std");
const builtin = @import("builtin");

const serial = switch (builtin.cpu.arch) {
    .aarch64 => @import("serial_aarch64.zig"),
    .riscv64 => @import("serial_riscv64.zig"),
    .x86_64 => @import("serial_x86_64.zig"),
    else => @compileError("serial: unsupported architecture"),
};

pub fn init() void {
    serial.init();
}

const vtable: std.Io.Writer.VTable = .{ .drain = drain };

/// print to serial, formatting the string first.
/// silently returns on error.
/// inted for use in "printf debugging"
pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    var w: std.Io.Writer = .{ .vtable = &vtable, .buffer = &buf, .end = 0 };
    w.print(fmt, args) catch return;
    w.flush() catch return;
}

/// write a string to serial port.
/// it will transate any \n to \r\n.
pub fn write(s: []const u8) void {
    for (s) |c| {
        if (c == '\n') {
            putchar('\r');
        }
        putchar(c);
    }
}

/// Put a char on the serial link
pub fn putchar(c: u8) void {
    serial.putchar(c);
}

fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
    const slice = data[0 .. data.len - 1];
    const pattern = data[slice.len];
    var written: usize = 0;

    for (w.buffer[0..w.end]) |byte| putchar(byte);
    w.end = 0;

    for (slice) |bytes| {
        for (bytes) |byte| putchar(byte);
        written += bytes.len;
    }

    for (0..splat) |_| for (pattern) |byte| putchar(byte);
    written += pattern.len * splat;
    return written;
}
