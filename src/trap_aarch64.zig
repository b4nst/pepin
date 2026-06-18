const std = @import("std");

pub const TrapFrame = extern struct {
    x: [31]u64, // the saved registers
    esr: u64,
    elr: u64,
    far: u64,
    spsr: u64,

    pub fn format(self: @This(), w: *std.Io.Writer) std.Io.Writer.Error!void {
        const ec = self.getExceptionClass();
        try w.print("[{s}] elr={x:0>16} far={x:0>16}\n", .{ self.getExceptionClassName(), self.elr, self.far });
        try w.print("  esr={x:0>16} spsr={x:0>16}\n", .{ self.esr, self.spsr });

        // For aborts, decode the fault status code (and write/read for data aborts)
        switch (ec) {
            0x20, 0x21, 0x24, 0x25 => {
                const is_data = ec == 0x24 or ec == 0x25;
                const wnr = (self.esr >> 6) & 1; // ISS[6], data aborts only
                try w.print("  {s}{s}\n", .{
                    self.getFaultName(),
                    if (is_data) (if (wnr != 0) " on write" else " on read") else "",
                });
            },
            else => {},
        }

        // register dump, x0..x30
        var i: usize = 0;
        while (i < self.x.len) : (i += 1) {
            try w.print("  x{d:0>2}={x:0>16}", .{ i, self.x[i] });
            if ((i + 1) % 3 == 0) try w.writeAll("\n");
        }
        try w.writeAll("\n");
    }

    fn getFSC(self: @This()) u6 {
        return @truncate(self.esr); // ISS[5:0] = (D|I)FSC
    }

    fn getFaultName(self: @This()) []const u8 {
        const fsc = self.getFSC();
        return switch (fsc) {
            0x00...0x03 => "address size fault",
            0x04 => "translation fault, level 0",
            0x05 => "translation fault, level 1",
            0x06 => "translation fault, level 2",
            0x07 => "translation fault, level 3",
            0x08...0x0b => "access flag fault",
            0x0c => "permission fault, level 0",
            0x0d => "permission fault, level 1",
            0x0e => "permission fault, level 2",
            0x0f => "permission fault, level 3",
            0x21 => "alignment fault",
            0x10 => "external abort",
            else => "fault",
        };
    }

    fn getExceptionClass(self: @This()) u6 {
        return @truncate(self.esr >> 26); // ESR_EL1[31:26] = Exception Class
    }

    fn getExceptionClassName(self: @This()) []const u8 {
        const ec = self.getExceptionClass();
        return switch (ec) {
            0x00 => "unknown",
            0x01 => "trapped WFI/WFE",
            0x07 => "SIMD/FP access trap",
            0x0e => "illegal execution state",
            0x15 => "SVC (syscall)",
            0x18 => "trapped MSR/MRS/sys",
            0x20 => "instruction abort (lower EL)",
            0x21 => "instruction abort (same EL)",
            0x22 => "PC alignment fault",
            0x24 => "data abort (lower EL)",
            0x25 => "data abort (same EL)",
            0x26 => "SP alignment fault",
            0x2c => "trapped FP",
            0x2f => "SError",
            0x30, 0x31 => "breakpoint",
            0x32, 0x33 => "software step",
            0x34, 0x35 => "watchpoint",
            0x3c => "BRK instruction",
            else => "other",
        };
    }
};

pub fn init() void {
    promote();
    // register the vector table
    asm volatile ("msr vbar_el1, %[t]"
        :
        : [t] "r" (&vectorTable),
        : .{ .memory = true });
}

/// Promote kernel to EL1h
fn promote() void {
    asm volatile (
        \\mov x9, sp        // current (valid Limine) stack value
        \\msr spsel, #1     // make SP_EL1 the active SP   (legal at EL1)
        \\mov sp, x9        // SP_EL1 = that value          (mov sp,x is legal; msr SP_EL1 is not)
        ::: .{ .x9 = true, .memory = true });
}

pub fn hcf() noreturn {
    while (true) asm volatile ("wfi"); // wait for interrupt
}

export fn stub() callconv(.naked) void {
    asm volatile (
        \\sub sp, sp, #288 // FRAME_SIZE = 31×8 + 4×8 = 280, round up to 288 for 16-byte SP alignment
        \\stp x0, x1,   [sp, #0] // save registers
        \\stp x2, x3,   [sp, #16]
        \\stp x4, x5,   [sp, #32]
        \\stp x6, x7,   [sp, #48]
        \\stp x8, x9,   [sp, #64]
        \\stp x10, x11, [sp, #80]
        \\stp x12, x13, [sp, #96]
        \\stp x14, x15, [sp, #112]
        \\stp x16, x17, [sp, #128]
        \\stp x18, x19, [sp, #144]
        \\stp x20, x21, [sp, #160]
        \\stp x22, x23, [sp, #176]
        \\stp x24, x25, [sp, #192]
        \\stp x26, x27, [sp, #208]
        \\stp x28, x29, [sp, #224]
        \\str x30,      [sp, #240]
        \\mrs x0, esr_el1
        \\mrs x1, elr_el1
        \\mrs x2, far_el1
        \\mrs x3, spsr_el1
        \\stp x0, x1, [sp, #248] // esr, elr
        \\stp x2, x3, [sp, #264] // far, spsr
        \\mov x0, sp // arg0 = frame pointer (AAPCS: first arg in x0)
        \\bl trapHandler // our handler in trap.zig
        \\ldr x30,      [sp, #240] // restore registers
        \\ldp x28, x29, [sp, #224]
        \\ldp x26, x27, [sp, #208]
        \\ldp x24, x25, [sp, #192]
        \\ldp x22, x23, [sp, #176]
        \\ldp x20, x21, [sp, #160]
        \\ldp x18, x19, [sp, #144]
        \\ldp x16, x17, [sp, #128]
        \\ldp x14, x15, [sp, #112]
        \\ldp x12, x13, [sp, #96]
        \\ldp x10, x11, [sp, #80]
        \\ldp x8, x9,   [sp, #64]
        \\ldp x6, x7,   [sp, #48]
        \\ldp x4, x5,   [sp, #32]
        \\ldp x2, x3,   [sp, #16]
        \\ldp x0, x1,   [sp, #0]
        \\add sp, sp, #288
        \\eret
    );
}

export fn unhandled() callconv(.naked) void {
    asm volatile ("b unhandled"); // to inifinity and beyond
}

export fn vectorTable() align(0x800) callconv(.naked) void {
    asm volatile (
        \\.balign 0x800
        // --- EL1t (SP_EL0) group, 0x000 ---
        \\.balign 0x80
        \\ b unhandled
        \\.balign 0x80
        \\ b unhandled
        \\.balign 0x80
        \\ b unhandled
        \\.balign 0x80
        \\ b unhandled
        // --- EL1h (SP_ELx) group, 0x200 ---  ← our kernel is here
        \\.balign 0x80
        \\ b stub          // sync
        \\.balign 0x80
        \\ b stub          // irq
        \\.balign 0x80
        \\ b stub          // fiq
        \\.balign 0x80
        \\ b stub          // serror
        // --- Lower EL AArch64, 0x400 (8 more entries) ---
        \\.balign 0x80
        \\ b unhandled
        \\.balign 0x80
        \\ b unhandled
        \\.balign 0x80
        \\ b unhandled
        \\.balign 0x80
        \\ b unhandled
        \\.balign 0x80
        \\ b unhandled
        \\.balign 0x80
        \\ b unhandled
        \\.balign 0x80
        \\ b unhandled
        \\.balign 0x80
        \\ b unhandled
    );
}
