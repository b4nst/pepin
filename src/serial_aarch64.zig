const mem = @import("mem/root.zig");

const UART_VA = 0xffff_9000_0000_0000;
const UART_PA = 0x0900_0000;

pub fn init() void {
    mem.vmm.map(UART_VA, UART_PA, .{ .writable = true, .device = true });
}

pub fn putchar(c: u8) void {
    const dr: *volatile u32 = @ptrFromInt(UART_VA);
    const fr: *volatile u32 = @ptrFromInt(UART_VA + 0x18);
    const txffmask = 0x20; // transmit FIFO full is on bit 5 of the flag register

    while (fr.* & txffmask != 0) {}
    dr.* = c;
}
