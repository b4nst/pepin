const std = @import("std");
const builtin = @import("builtin");
const limine = @import("limine");

const pmm = @import("pmm.zig");
const serial = @import("serial.zig");

pub const panic = std.debug.FullPanic(caravanPalace);

fn caravanPalace(_: []const u8, _: ?usize) noreturn {
    // for now just halt and catch fire
    hcf();
}

// Export markers
export var base_rev: limine.BaseRevision linksection(".limine_requests") = .{ .revision = 6 };
export var hhdm_request: limine.HhdmRequest linksection(".limine_requests") = .{};
export var mm_request: limine.MemoryMapRequest linksection(".limine_requests") = .{};
// export var framebuffer_request: limine.FramebufferRequest linksection(".limine_requests") = .{};

// This can be anywhere but needs to be somewhere.
export var start_marker: limine.RequestsStartMarker linksection(".limine_requests_start") = .{};
export var end_marker: limine.RequestsEndMarker linksection(".limine_requests_end") = .{};

// Halt and catch fire function.
fn hcf() noreturn {
    while (true) {
        switch (builtin.cpu.arch) {
            .aarch64 => asm volatile ("wfi"), // wait for interrupt
            .loongarch64 => asm volatile ("idle 0"),
            .riscv64 => asm volatile ("wfi"),
            .x86_64 => asm volatile ("hlt"),
            else => unreachable, // we don't support other architectures
        }
    }
}

// Export to avoid linkage name-mangling
export fn kmain() noreturn {
    // Ensure the bootloader actually understands our base revision (see spec).
    if (!base_rev.isSupported()) {
        @panic("unsupported limine base revision");
    }

    const mm_response = mm_request.response orelse @panic("failed to get memory map from limine");
    const hhdm_response = hhdm_request.response orelse @panic("failed to get HHDM response from limine");

    // Init memory manager
    const blocks = pmm.init(mm_response, hhdm_response);

    // wipe bootloader menu
    serial.write("\x1b[2J\x1b[H");

    serial.print("initialized {d} blocks", .{blocks});

    serial.write("hello from pepin\r\n");
    hcf();
}
