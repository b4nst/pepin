const limine = @import("limine");

pub const vmm = @import("vmm.zig");
pub const pmm = @import("pmm.zig");

pub fn init(memmap: *const limine.MemoryMapResponse, hhdm: *const limine.HhdmResponse) usize {
    const blocks = pmm.init(memmap, hhdm);
    vmm.init(hhdm);
    return blocks;
}
