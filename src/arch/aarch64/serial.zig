pub fn putchar(c: u8) void {
    const base = 0x09000000;
    const dr: *volatile u32 = @ptrFromInt(base);
    const fr: *volatile u32 = @ptrFromInt(base + 0x18);
    const txffmask = 0x20; // transmit FIFO full is on bit 5 of the flag register

    while (fr.* & txffmask != 0) {}
    dr.* = c;
}
