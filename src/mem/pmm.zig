// Physical memory manager
const std = @import("std");
const limine = @import("limine");

const PAGE_SIZE = 0x1000; // 4KiB

var head: usize = 0;
var hhdm_offset: ?usize = null;

pub fn init(memmap: *const limine.MemoryMapResponse, hhdm: *const limine.HhdmResponse) usize {
    var block_count: usize = 0;
    hhdm_offset = hhdm.offset;

    for (memmap.getEntries()) |entry| {
        if (entry.type != .usable) continue;
        block_count += initBlock(entry);
    }

    return block_count;
}

fn initBlock(block: *const limine.MemoryMapEntry) usize {
    const end = block.base + block.length;
    var offset = std.mem.alignForward(usize, block.base, PAGE_SIZE);
    var block_count: usize = 0;

    while (offset + PAGE_SIZE <= end) : (offset += PAGE_SIZE) {
        if (offset == 0) continue; // skip address 0 to avoid confusion
        const vaddr: *u64 = @ptrFromInt(offset + hhdm_offset.?);
        vaddr.* = head;
        head = offset;
        block_count += 1;
    }

    return block_count;
}

pub fn alloc() ?usize {
    const off = hhdm_offset orelse @panic("pmm: alloc called before init");
    if (head == 0) return null; // no memory left

    const vaddr: *u64 = @ptrFromInt(head + off);
    defer head = vaddr.*;
    return head;
}

pub fn allocZeroed() ?usize {
    const off = hhdm_offset orelse @panic("pmm: allocZeroed called before init");
    const frame = alloc() orelse return null;
    const bytes: *[PAGE_SIZE]u8 = @ptrFromInt(frame + off);
    @memset(bytes, 0);
    return frame;
}

pub fn free(frame: usize) void {
    const off = hhdm_offset orelse @panic("pmm: free called before init");
    const vaddr: *u64 = @ptrFromInt(frame + off);
    vaddr.* = head;
    head = frame;
}
