const builtin = @import("builtin");
const std = @import("std");
const limine = @import("limine");

const mem = @import("mem/root.zig");
const serial = @import("serial.zig");
const trap = @import("trap.zig");

// override panic
pub const panic = std.debug.FullPanic(trap.caravanPalace);

// Export markers
export var base_rev: limine.BaseRevision linksection(".limine_requests") = .{ .revision = 6 };
export var hhdm_request: limine.HhdmRequest linksection(".limine_requests") = .{};
export var mm_request: limine.MemoryMapRequest linksection(".limine_requests") = .{};
// export var framebuffer_request: limine.FramebufferRequest linksection(".limine_requests") = .{};

// This can be anywhere but needs to be somewhere.
export var start_marker: limine.RequestsStartMarker linksection(".limine_requests_start") = .{};
export var end_marker: limine.RequestsEndMarker linksection(".limine_requests_end") = .{};

fn init() void {
    const mm_response = mm_request.response orelse @panic("failed to get memory map from limine");
    const hhdm_response = hhdm_request.response orelse @panic("failed to get HHDM response from limine");

    trap.init();
    // memory
    const blocks = mem.init(mm_response, hhdm_response);
    // serial
    serial.init();
    // wipe bootloader menu
    serial.write("\x1b[2J\x1b[H");
    serial.print("initialized {d} blocks\n", .{blocks});
}

// Export to avoid linkage name-mangling
export fn kmain() noreturn {
    // Ensure the bootloader actually understands our base revision (see spec).
    if (!base_rev.isSupported()) {
        @panic("unsupported limine base revision");
    }

    init();

    const p: *volatile u64 = @ptrFromInt(0xdead0000);
    p.* = 1;

    serial.write("hello from pepin\r\n");
    trap.hcf();
}
