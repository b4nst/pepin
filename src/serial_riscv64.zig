const mem = @import("mem/root.zig");

const UART_VA = 0xffff_9000_0000_0000;
const UART_PA = 0x10000000;

pub fn init() void {
    mem.vmm.map(UART_VA, UART_PA, .{ .writable = true, .device = true });
}

pub fn putchar(c: u8) void {
    const dr: *volatile u8 = @ptrFromInt(UART_VA);
    const lsr: *volatile u8 = @ptrFromInt(UART_VA + 0x5);
    const thremask = 0x20; // bit 5 of lsr

    while (lsr.* & thremask == 0) {}
    dr.* = c;
}
