// Physical memory manager
const std = @import("std");
const limine = @import("limine");

var head: usize = 0;
var hhdm_offset: usize = undefined;

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
    const page_size = 0x1000; // 4KiB
    const end = block.base + block.length;
    var offset = std.mem.alignForward(usize, block.base, page_size);
    var block_count: usize = 0;

    while (offset + page_size <= end) : (offset += page_size) {
        if (offset == 0) continue; // skip address 0 to avoid confusion
        const vaddr: *u64 = @ptrFromInt(offset + hhdm_offset);
        vaddr.* = head;
        head = offset;
        block_count += 1;
    }

    return block_count;
}

pub fn alloc() ?usize {
    if (head == 0) return null; // no memory left

    const vaddr: *u64 = @ptrFromInt(head + hhdm_offset);
    defer head = vaddr.*;
    return head;
}

pub fn free(frame: usize) void {
    const vaddr: *u64 = @ptrFromInt(frame + hhdm_offset);
    vaddr.* = head;
    head = frame;
}
