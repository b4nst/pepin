const pmm = @import("pmm.zig");
const paging = @import("paging.zig");

const Pte = packed struct(u64) {
    valid: bool = false,
    read: bool = false,
    write: bool = false,
    execute: bool = false,
    user: bool = false,
    global: bool = false,
    accessed: bool = false,
    dirty: bool = false,
    rsw: u2 = 0, // 8..9 reserved for software
    ppn: u44 = 0, // 10..53 physical page number
    _reserved: u7 = 0, // 54..60
    svpbmt: u2 = 0,
    svnapot: bool = false,
};

fn encode(phys: usize, f: paging.Flags) u64 {
    return @bitCast(Pte{
        .valid = true,
        .read = true,
        .write = f.writable,
        .execute = f.executable,
        .user = f.user,
        .accessed = true,
        .dirty = f.writable,
        .global = !f.user,
        .ppn = @intCast(phys >> 12),
    });
}

pub fn map(hhdm_offset: usize, virt: usize, phys: usize, flags: paging.Flags) void {
    const satp = read_satp();
    var table_phys = (satp & 0xFFF_FFFF_FFFF) << 12; // PPN (44 bits) << 12
    const mode = (satp >> 60) & 0xF;
    if (mode != 8 and mode != 9) @panic("unexpected satp mode");
    const levels = mode - 5;

    // descend the upper levels: L from levels-1 down to 1
    var l: usize = levels - 1;
    while (l >= 1) : (l -= 1) {
        const idx = (virt >> @intCast(12 + 9 * l)) & 511;
        const table: *[512]u64 = @ptrFromInt(table_phys + hhdm_offset);
        const e: Pte = @bitCast(table[idx]);

        if (e.valid) {
            if (e.read or e.write or e.execute) @panic("huge page on descent");
            table_phys = @as(usize, e.ppn) << 12;
        } else {
            // alloc the table
            const new = pmm.allocZeroed() orelse @panic("oom");
            table[idx] = @bitCast(Pte{ .valid = true, .ppn = @intCast(new >> 12) });
            table_phys = new;
        }
    }

    const leaf_idx = (virt >> 12) & 511;
    const pt: *[512]u64 = @ptrFromInt(table_phys + hhdm_offset);
    pt[leaf_idx] = encode(phys, flags);

    flush_tlb(virt); // flush the stale TLB line
}

fn read_satp() usize {
    return asm volatile ("csrr %[out], satp"
        : [out] "=r" (-> usize),
    );
}

fn flush_tlb(addr: usize) void {
    asm volatile ("sfence.vma %[addr]"
        :
        : [addr] "r" (addr),
        : .{ .memory = true });
}
