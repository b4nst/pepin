pub fn init() void {}

pub fn putchar(c: u8) void {
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
