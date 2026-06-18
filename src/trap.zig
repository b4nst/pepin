const builtin = @import("builtin");
const serial = @import("serial.zig");
const trap = switch (builtin.cpu.arch) {
    .aarch64 => @import("trap_aarch64.zig"),
    .riscv64 => @import("trap_riscv64.zig"),
    .x86_64 => @import("trap_x86_64.zig"),
    else => @compileError("trap: unsupported architecture"),
};

pub const init = trap.init;
pub const hcf = trap.hcf;

// callconv(.c) so the stub's call + rdi argument match the SysV ABI.
export fn trapHandler(frame: *trap.TrapFrame) callconv(.c) void {
    serial.print("\n*** TRAP ***\n{f}\n", .{frame.*});
    hcf();
}

// custom @panic handler
pub fn caravanPalace(msg: []const u8, _: ?usize) noreturn {
    serial.print("FATAL: {s}\n", .{msg});
    // for now just halt and catch fire
    hcf();
}
