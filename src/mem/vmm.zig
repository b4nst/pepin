const builtin = @import("builtin");
const limine = @import("limine");

const paging = @import("paging.zig");
const vmm = switch (builtin.cpu.arch) {
    .aarch64 => @import("vmm_aarch64.zig"),
    .riscv64 => @import("vmm_riscv64.zig"),
    .x86_64 => @import("vmm_x86_64.zig"),
    else => @compileError("virtual memory manager: unsupported architecture"),
};

pub const Flags = paging.Flags;
var hhdm_offset: ?usize = null;

pub fn init(hhdm: *const limine.HhdmResponse) void {
    hhdm_offset = hhdm.offset;
}

pub fn map(virt: usize, phys: usize, flags: Flags) void {
    const off = hhdm_offset orelse @panic("vmm.map called before vmm.init");
    vmm.map(off, virt, phys, flags);
}
