const std = @import("std");

pub const TrapFrame = extern struct {
    x: [31]u64,
    /// supervisor exception program counter
    sepc: u64,
    scause: u64,
    stval: u64,
    sstatus: u64,

    pub fn format(self: @This(), w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("[{s}] sepc={x:0>16} stval={x:0>16}\n", .{ self.causeName(), self.sepc, self.stval });
        try w.print("  scause={x:0>16} sstatus={x:0>16}\n", .{ self.scause, self.sstatus });
        var i: usize = 0;
        while (i < self.x.len) : (i += 1) {
            try w.print("  x{d:0>2}={x:0>16}", .{ i + 1, self.x[i] }); // x[i] holds register x(i+1)
            if ((i + 1) % 3 == 0) try w.writeAll("\n");
        }
        try w.writeAll("\n");
    }

    fn causeName(self: @This()) []const u8 {
        const interrupt = (self.scause >> 63) != 0;
        const code: u63 = @truncate(self.scause);
        if (interrupt) return switch (code) {
            1 => "supervisor software interrupt",
            5 => "supervisor timer interrupt",
            9 => "supervisor external interrupt",
            else => "interrupt",
        };
        return switch (code) {
            0 => "instruction address misaligned",
            1 => "instruction access fault",
            2 => "illegal instruction",
            3 => "breakpoint",
            4 => "load address misaligned",
            5 => "load access fault",
            6 => "store/AMO address misaligned",
            7 => "store/AMO access fault",
            8 => "ecall from U-mode",
            9 => "ecall from S-mode",
            12 => "instruction page fault",
            13 => "load page fault",
            15 => "store/AMO page fault",
            else => "exception",
        };
    }
};

pub fn init() void {
    // register the stub
    asm volatile ("csrw stvec, %[t]"
        :
        : [t] "r" (&stub),
        : .{ .memory = true });
}

pub fn hcf() noreturn {
    while (true) asm volatile ("wfi");
}

export fn stub() align(4) callconv(.naked) void {
    asm volatile (
    // Make room in sp
        \\addi sp, sp, -288
        // push GPRs
        \\sd x1, 0(sp) 
        \\sd x3, 16(sp)
        // skip x2 as it is sp.
        \\sd x5, 32(sp) // x5 = t0, we can use it after this line
        \\sd x6, 40(sp)
        \\sd x7, 48(sp)
        \\sd x8, 56(sp)
        \\sd x9, 64(sp)
        \\sd x10, 72(sp)
        \\sd x11, 80(sp)
        \\sd x12, 88(sp)
        \\sd x13, 96(sp)
        \\sd x14, 104(sp)
        \\sd x15, 112(sp)
        \\sd x16, 120(sp)
        \\sd x17, 128(sp)
        \\sd x18, 136(sp)
        \\sd x19, 144(sp)
        \\sd x20, 152(sp)
        \\sd x21, 160(sp)
        \\sd x22, 168(sp)
        \\sd x23, 176(sp)
        \\sd x24, 184(sp)
        \\sd x25, 192(sp)
        \\sd x26, 200(sp)
        \\sd x27, 208(sp)
        \\sd x28, 216(sp)
        \\sd x29, 224(sp)
        \\sd x30, 232(sp)
        \\sd x31, 240(sp)
        // original sp
        \\addi t0, sp, 288 // t0 is now sp = x2
        \\sd t0, 8(sp) // store x2 at the right offset
        \\csrr t0, sepc // and the four CSRs, via the now-free t0
        \\sd t0, 248(sp)
        \\csrr t0, scause
        \\sd t0, 256(sp)
        \\csrr t0, stval
        \\sd t0, 264(sp)
        \\csrr t0, sstatus
        \\sd t0, 272(sp)
        // call trap
        \\mv a0, sp
        \\call trapHandler
        // reload the return state from the frame (handler may have edited sepc for resume)
        \\ld t0, 248(sp)
        \\csrw sepc, t0
        \\ld t0, 272(sp)
        \\csrw sstatus, t0
        // pop registers
        \\ld x31, 240(sp)
        \\ld x30, 232(sp)
        \\ld x29, 224(sp)
        \\ld x28, 216(sp)
        \\ld x27, 208(sp)
        \\ld x26, 200(sp)
        \\ld x25, 192(sp)
        \\ld x24, 184(sp)
        \\ld x23, 176(sp)
        \\ld x22, 168(sp)
        \\ld x21, 160(sp)
        \\ld x20, 152(sp)
        \\ld x19, 144(sp)
        \\ld x18, 136(sp)
        \\ld x17, 128(sp)
        \\ld x16, 120(sp)
        \\ld x15, 112(sp)
        \\ld x14, 104(sp)
        \\ld x13, 96(sp)
        \\ld x12, 88(sp)
        \\ld x11, 80(sp)
        \\ld x10, 72(sp)
        \\ld x9, 64(sp)
        \\ld x8, 56(sp)
        \\ld x7, 48(sp)
        \\ld x6, 40(sp)
        \\ld x5, 32(sp) // x5 = t0, we can use it after this line
        \\ld x3, 16(sp)
        \\ld x1, 0(sp) 
        // return
        \\addi sp, sp, 288
        \\sret
    );
}
