pub fn putchar(c: u8) void {
    const base = 0x10000000;
    const dr: *volatile u8 = @ptrFromInt(base);
    const lsr: *volatile u8 = @ptrFromInt(base + 0x5);
    const thremask = 0x20; // bit 5 of lsr

    while (lsr.* & thremask == 0) {}
    dr.* = c;
}
