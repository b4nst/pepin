const std = @import("std");
const serial = @import("serial.zig");

pub const TrapFrame = extern struct {
    // pushed by the stub, in this order so the struct matches memory low→high:
    r15: u64,
    r14: u64,
    r13: u64,
    r12: u64,
    r11: u64,
    r10: u64,
    r9: u64,
    r8: u64,
    rbp: u64,
    rdi: u64,
    rsi: u64,
    rdx: u64,
    rcx: u64,
    rbx: u64,
    rax: u64,
    vector: u64,
    error_code: u64,
    // pushed by the CPU automatically:
    rip: u64,
    cs: u64,
    rflags: u64,
    rsp: u64,
    ss: u64,

    pub fn format(self: @This(), w: *std.Io.Writer) std.Io.Writer.Error!void {
        const vname = self.vectorName();
        try w.print("[{s}] ", .{vname});
        try w.writeAll("\n");
        try self.writeError(w);
        try w.writeAll("\n");
        comptime var i: usize = 0;
        inline for (std.meta.fields(@This())) |field| {
            try w.print("{s:>11}={x:0>16}  ", .{ field.name, @field(self, field.name) });
            i += 1;
            if (i % 3 == 0) try w.writeAll("\n");
        }
        // cr registries
        try w.writeAll("\n");
        try w.print("cr0={x:0>16} cr2={x:0>16} cr3={x:0>16} cr4={x:0>16}", .{
            getReg("cr0"),
            getReg("cr2"),
            getReg("cr3"),
            getReg("cr4"),
        });
    }

    fn writeError(self: @This(), w: *std.Io.Writer) std.Io.Writer.Error!void {
        const e = self.error_code;
        switch (self.vector) {
            14 => { // #PF — decode the page-fault bits
                try w.print("err={x} [", .{e});
                try w.writeAll(if (e & 1 != 0) "protection" else "not-present");
                try w.writeAll(if (e & 2 != 0) ", write" else ", read");
                try w.writeAll(if (e & 4 != 0) ", user" else ", supervisor");
                if (e & 8 != 0) try w.writeAll(", reserved-bit");
                if (e & 16 != 0) try w.writeAll(", instr-fetch");
                try w.writeAll("]");
            },
            8, 10, 11, 12, 13, 17, 21 => { // selector-style error code
                if (e == 0) {
                    try w.writeAll("err=0");
                } else {
                    try w.print("err={x} [sel={x} {s}{s}]", .{
                        e,                                                           e & 0xfff8,
                        if (e & 2 != 0) "IDT" else if (e & 4 != 0) "LDT" else "GDT", if (e & 1 != 0) " external" else "",
                    });
                }
            },
            else => try w.writeAll("err=n/a"), // these vectors push no error code
        }
    }

    fn vectorName(self: @This()) []const u8 {
        return switch (self.vector) {
            0 => "#DE divide error",
            1 => "#DB debug",
            2 => "NMI non-maskable interrupt",
            3 => "#BP breakpoint",
            4 => "#OF overflow",
            5 => "#BR bound range exceeded",
            6 => "#UD invalid opcode",
            7 => "#NM device not available",
            8 => "#DF double fault",
            9 => "coprocessor segment overrun (legacy/reserved)",
            10 => "#TS invalid TSS",
            11 => "#NP segment not present",
            12 => "#SS stack-segment fault",
            13 => "#GP general protection",
            14 => "#PF page fault",
            15 => "reserved",
            16 => "#MF x87 floating-point",
            17 => "#AC alignment check",
            18 => "#MC machine check",
            19 => "#XM SIMD floating-point",
            20 => "#VE virtualization",
            21 => "#CP control-protection",
            22...27 => "reserved",
            28 => "#HV hypervisor injection",
            29 => "#VC VMM communication",
            30 => "#SX security",
            31 => "reserved",
            32...255 => "hardware interrupt",
            else => "unknown", // v > 255 can't really happen, but u64 switch needs it
        };
    }
};

const GateDescriptor = packed struct(u128) {
    offset_low: u16 = 0, // handler address bits 0..15
    selector: u16 = 0, // code segment selector (basically pepin CS)
    ist: u3 = 0, // interrupt stack table index (0 = use current stack)
    _reserved: u5 = 0,
    gate_type: u4 = 0, // 0xe = 64 bits interrupt gate, 0xf = trap gate
    _zero: u1 = 0,
    dpl: u2 = 0, // privilege level allowed to invoke (0 = kernel only)
    present: bool = false, // must be true
    offset_mid: u16 = 0, // handler addr bits 16..31
    offset_high: u32 = 0, // handler addr bits 32..63
    _reserved1: u32 = 0,
};

const Idtr = packed struct {
    limit: u16, // sizeof(idt) -1
    base: u64, // address of the idt array
};

var idt: [256]GateDescriptor = @splat(.{});

pub fn init() void {
    for (stubs, 0..) |s, i| setGate(&idt[i], @intFromPtr(s));
    const idtr = Idtr{ .limit = @sizeOf(@TypeOf(idt)) - 1, .base = @intFromPtr(&idt) };
    loadIdt(&idtr);
}

// Halt and catch fire function.
pub fn hcf() noreturn {
    while (true) asm volatile ("hlt");
}

const stubs = blk: {
    var arr: [256]*const fn () callconv(.naked) void = undefined;
    for (&arr, 0..) |*s, i| s.* = makeStub(@intCast(i));
    break :blk arr;
};

fn loadIdt(idtr: *const Idtr) void {
    asm volatile ("lidt (%[p])"
        :
        : [p] "r" (idtr),
        : .{ .memory = true });
}

fn setGate(g: *GateDescriptor, addr: usize) void {
    g.gate_type = 0xe;
    g.present = true;
    g.dpl = 0;
    g.selector = @truncate(getReg("cs")); // selector is 16 bits
    g.offset_low = @truncate(addr);
    g.offset_mid = @truncate(addr >> 16);
    g.offset_high = @truncate(addr >> 32);
}

fn getReg(comptime reg: []const u8) usize {
    return asm volatile ("mov %%" ++ reg ++ ", %[o]"
        : [o] "=r" (-> usize),
    );
}

export fn commonStub() callconv(.naked) void {
    asm volatile (
        \\ push %rax
        \\ push %rbx
        \\ push %rcx
        \\ push %rdx
        \\ push %rsi
        \\ push %rdi
        \\ push %rbp
        \\ push %r8
        \\ push %r9
        \\ push %r10
        \\ push %r11
        \\ push %r12
        \\ push %r13
        \\ push %r14
        \\ push %r15
        \\ mov %rsp, %rdi   // arg0 = pointer to the trap frame (current RSP)
        \\ call trapHandler
        \\ pop %r15
        \\ pop %r14
        \\ pop %r13
        \\ pop %r12
        \\ pop %r11
        \\ pop %r10
        \\ pop %r9
        \\ pop %r8
        \\ pop %rbp
        \\ pop %rdi
        \\ pop %rsi
        \\ pop %rdx
        \\ pop %rcx
        \\ pop %rbx
        \\ pop %rax
        \\ add $16, %rsp    // discard vector + error_code
        \\ iretq            // restore RIP/CS/RFLAGS/RSP/SS, resume
    );
}

fn hasErrorCode(vec: u8) bool {
    return switch (vec) {
        8, 10, 11, 12, 13, 14, 17, 21 => true, // #DF #TS #NP #SS #GP #PF #AC #CP
        else => false,
    };
}

fn makeStub(comptime vec: u8) *const fn () callconv(.naked) void {
    return &struct {
        fn stub() callconv(.naked) void {
            asm volatile ((if (hasErrorCode(vec)) "" else "push $0\n") ++ // dummy errcode only when the CPU didn't push one
                    std.fmt.comptimePrint("push ${d}\njmp commonStub", .{vec}));
        }
    }.stub;
}
