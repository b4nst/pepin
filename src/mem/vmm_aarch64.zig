const pmm = @import("pmm.zig");
const paging = @import("paging.zig");

const MairIdx = enum(u3) {
    normal = 0,
    device = 1,
};

const Pte = packed struct(u64) {
    valid: bool = true,
    type: bool = false,
    attrIndx: MairIdx = .normal, // bit 2..4
    _blank: bool = false,
    user: bool = false, // bit 6
    readonly: bool = true, // bit 7
    sh: u2 = 0,
    _af: bool = true, // bit 10
    _blank2: bool = false,
    addr: u36 = 0, // frame, bits 12..47
    _blank3: u5 = 0,
    pxn: bool = false,
    uxn: bool = false,
    _high: u9 = 0,
};

fn encode(phys: usize, f: paging.Flags) u64 {
    return @bitCast(Pte{
        .type = true,
        .readonly = !f.writable,
        .user = f.user,
        .uxn = !(f.user and f.executable),
        .pxn = !(!f.user and f.executable),
        .attrIndx = if (f.device) .device else .normal,
        .addr = @intCast(phys >> 12),
    });
}

/// default flags for intermediate page tables.
const intermediate: paging.Flags = .{
    .executable = true,
    .user = true,
    .writable = true,
};

pub fn map(hhdm_offset: usize, virt: usize, phys: usize, flags: paging.Flags) void {
    const tables: [4]usize = .{
        (virt >> 39) & 511, // PML4
        (virt >> 30) & 511, // PDPT
        (virt >> 21) & 511, // PD
        (virt >> 12) & 511, // PT
    };

    const addr_mask = 0x0000_FFFF_FFFF_F000;
    var table_phys = read_ttbr(true) & addr_mask;

    // Walk the table tree
    for (tables[0..3]) |iN| {
        const table: *[512]u64 = @ptrFromInt(table_phys + hhdm_offset);
        const e: Pte = @bitCast(table[iN]);
        if (e.valid and e.type) {
            table_phys = @as(usize, e.addr) << 12;
        } else if (e.valid and !e.type) {
            @panic("huge page on descent");
        } else {
            // alloc the table
            const new = pmm.allocZeroed() orelse @panic("todo return error");
            table[iN] = encode(new, intermediate);
            table_phys = new;
        }
    }

    const pt: *[512]u64 = @ptrFromInt(table_phys + hhdm_offset);
    pt[tables[3]] = encode(phys, flags);

    flush_tlb(virt); // flush the stale TLB line
}

fn read_ttbr(comptime high: bool) usize {
    const reg = if (high) "TTBR1_EL1" else "TTBR0_EL1";
    return asm volatile ("mrs %[out], " ++ reg
        : [out] "=r" (-> usize),
    );
}

fn flush_tlb(addr: usize) void {
    const page = addr >> 12;
    asm volatile (
        \\dsb ishst
        \\tlbi vaae1is, %[page]
        \\dsb ish
        \\isb
        :
        : [page] "r" (page),
        : .{ .memory = true } // don't reorder memory accesses across the flush
    );
}
