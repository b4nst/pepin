const pmm = @import("pmm.zig");
const paging = @import("paging.zig");

const PRESENT = 1;
const ADDR_MASK = 0x000F_FFFF_FFFF_F000;

const Pte = packed struct(u64) {
    present: bool = false,
    writable: bool = false,
    user: bool = false,
    pwt: bool = false,
    cache_disable: bool = false,
    _low: u7 = 0,
    addr: u40 = 0, // frame, bits 12..51
    _high: u11 = 0,
    no_execute: bool = false, // bit 63
};

fn encode(phys: usize, f: paging.Flags) u64 {
    return @bitCast(Pte{
        .present = true,
        .writable = f.writable,
        .user = f.user,
        .cache_disable = f.device, // MMIO → uncacheable
        .no_execute = !f.executable, // the x86 inversion, stated once, legibly
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

    var table_phys = read_cr3() & ADDR_MASK;

    // Walk the table tree
    for (tables[0..3]) |iN| {
        const table: *[512]u64 = @ptrFromInt(table_phys + hhdm_offset);
        const e = table[iN];
        if (e & PRESENT == 0) {
            // alloc the table
            const new = pmm.allocZeroed() orelse @panic("todo return error");
            table[iN] = encode(new, intermediate);
            table_phys = new;
        } else table_phys = e & ADDR_MASK;
    }

    const pt: *[512]u64 = @ptrFromInt(table_phys + hhdm_offset);
    pt[tables[3]] = encode(phys, flags);

    invlpg(virt); // flush the stale TLB line
}

fn read_cr3() usize {
    return asm volatile (
        \\mov %%cr3, %[out]
        : [out] "=r" (-> usize), // let the compiler select the registry
    );
}

fn invlpg(addr: usize) void {
    asm volatile (
        \\invlpg (%[addr])
        :
        : [addr] "r" (addr),
        : .{ .memory = true } // don't reorder memory accesses across the flush
    );
}
