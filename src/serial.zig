const builtin = @import("builtin");

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
    switch (builtin.cpu.arch) {
        .aarch64 => putcharAarch(c),
        .riscv64 => putcharRiscV(c),
        .x86_64 => putcharX86(c),
        else => @compileError("serial: unsupported arch"),
    }
}

fn putcharAarch(c: u8) void {
    _ = c;
}

fn putcharRiscV(c: u8) void {
    _ = c;
}

fn putcharX86(c: u8) void {
    const com1 = 0x3f8;
    const lsr = com1 + 5;
    const thremask = 0x20; // bit 5

    // busy poll to avoid writting on a busy line
    while (inb(lsr) & thremask == 0) {}

    outb(com1, c);
}

fn inb(port: u16) u8 {
    // COM1 is > 255 so we cannot in as immediate, we go through DX register first.
    // for reference this will translate to smthg like:
    // mov    %di, %dx    ; get `port` into dx
    // inb    %dx, %al    ; read port value into accumulator
    //
    // then zig return al with ={al} instruction.
    return asm volatile (
        \\inb %[port], %[result]
        : [result] "={al}" (-> u8),
        : [port] "{dx}" (port),
    );
}

fn outb(port: u16, val: u8) void {
    asm volatile (
        \\outb %[value], %[port]
        :
        : [value] "{al}" (val),
          [port] "{dx}" (port),
    );
}
