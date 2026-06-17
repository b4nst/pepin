const std = @import("std");

/// A list of architectures supported by the kernel.
const Arch = enum {
    x86_64,
    aarch64,
    riscv64,
    loongarch64,

    /// Convert the architecture to an std.Target.Cpu.Arch.
    fn toStd(self: @This()) std.Target.Cpu.Arch {
        return switch (self) {
            .x86_64 => .x86_64,
            .aarch64 => .aarch64,
            .riscv64 => .riscv64,
            .loongarch64 => .loongarch64,
        };
    }
};

/// Shell script to make an image
const mkimg_script =
    \\set -eu
    \\img=$1; efi=$2; conf=$3; kernel=$4
    \\mformat -i "$img" -C -T 131072 ::
    \\mmd     -i "$img" ::/EFI ::/EFI/BOOT
    \\mcopy   -i "$img" "$efi"    "::/EFI/BOOT/$(basename "$efi")"
    \\mcopy   -i "$img" "$conf"   ::/limine.conf
    \\mmd     -i "$img" ::/boot
    \\mcopy   -i "$img" "$kernel" ::/boot/kernel
;

/// Create a target query for the given architecture.
/// The target needs to disable some features that are not supported
/// in a bare-metal environment, such as SSE or AVX on x86_64.
fn targetQueryForArch(arch: Arch) std.Target.Query {
    var query: std.Target.Query = .{
        .cpu_arch = arch.toStd(),
        .os_tag = .freestanding,
        .abi = .none,
    };

    switch (arch) {
        .x86_64 => {
            const Target = std.Target.x86;

            query.cpu_features_add = Target.featureSet(&.{ .popcnt, .soft_float });
            query.cpu_features_sub = Target.featureSet(&.{ .avx, .avx2, .sse, .sse2, .mmx });
        },
        .aarch64 => {
            const Target = std.Target.aarch64;

            query.cpu_features_add = Target.featureSet(&.{});
            query.cpu_features_sub = Target.featureSet(&.{ .fp_armv8, .crypto, .neon });
        },
        .riscv64 => {
            const Target = std.Target.riscv;

            query.cpu_features_add = Target.featureSet(&.{});
            query.cpu_features_sub = Target.featureSet(&.{.d});
        },
        .loongarch64 => {},
    }

    return query;
}

pub fn build(b: *std.Build) void {
    const arch = b.option(Arch, "arch", "Architectue to build the kernel for") orelse .x86_64;

    const query = targetQueryForArch(arch);

    // Resolve the target query and the standard optimization options.
    // The optimization options can be overriden on the command line
    // by passing the `-Doptimize=<option>` flag to the build command.
    const target = b.resolveTargetQuery(query);
    const optimize = b.standardOptimizeOption(.{});

    // Create our limine wrapper module
    const limine_module = b.createModule(.{ .root_source_file = b.path("lib/limine/root.zig"), .target = target });

    // Create a module for the kernel.
    const kernel_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .sanitize_c = .off,
        .pic = false,
    });

    // Specify the code model and other target-specific options.
    switch (arch) {
        .x86_64 => {
            kernel_module.red_zone = false;
            kernel_module.code_model = .kernel;
        },
        .aarch64, .riscv64, .loongarch64 => {},
    }

    // Add the limine module as an import to the kernel module.
    kernel_module.addImport("limine", limine_module);

    // Create an executable for the kernel using the kernel module.
    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_module = kernel_module,
        .linkage = .static,
        .use_llvm = true, // Zig's self-hosted ELF linker is causing us troubles
    });

    // Set the linker script for the kernel based on the architecture.
    kernel.setLinkerScript(b.path(b.fmt("linker-{s}.lds", .{@tagName(arch)})));
    // remove unused sections
    kernel.link_function_sections = true;
    kernel.link_data_sections = true;
    kernel.link_gc_sections = true;
    kernel.entry = .{ .symbol_name = "kmain" };
    kernel.image_base = 0xffffffff80000000; // match our linker scripts to be in higher half

    // Add kernel install step
    const kinstall = b.addInstallArtifact(kernel, .{ .dest_dir = .{ .override = .{ .custom = b.fmt("bin-{s}", .{@tagName(arch)}) } } });
    b.getInstallStep().dependOn(&kinstall.step);

    // Make image
    const limine_dir = b.graph.environ_map.get("LIMINE_DIR") orelse std.debug.panic("LIMINE_DIR not set - please run inside devenv shell", .{});
    const efi_file = switch (arch) {
        .aarch64 => b.pathJoin(&.{ limine_dir, "BOOTAA64.EFI" }),
        .loongarch64 => b.pathJoin(&.{ limine_dir, "BOOTLOONGARCH64.EFI" }),
        .riscv64 => b.pathJoin(&.{ limine_dir, "BOOTRISCV64.EFI" }),
        .x86_64 => b.pathJoin(&.{ limine_dir, "BOOTX64.EFI" }),
    };
    const img_cmd = b.addSystemCommand(&.{ "sh", "-c", mkimg_script, "sh" });
    const image = img_cmd.addOutputFileArg("os.img");
    img_cmd.addFileArg(.{ .cwd_relative = efi_file });
    img_cmd.addFileArg(b.path("limine.conf"));
    img_cmd.addFileArg(kernel.getEmittedBin());

    // Add a build step to export the image
    const install_img = b.addInstallFile(image, b.fmt("os-{s}.img", .{@tagName(arch)}));
    const image_step = b.step("image", "Build the bootable disk image");
    image_step.dependOn(&install_img.step);

    // Launch QEMU
    const qemu = b.addSystemCommand(&.{getQEMUBin(arch)});
    switch (arch) {
        .aarch64 => {
            qemu.addArgs(&.{
                "-M",
                "virt",
                "-cpu",
                "cortex-a72",
            });
            const aavmf_code = b.graph.environ_map.get("AAVMF_CODE") orelse std.debug.panic("AAVMF_CODE not set - please run inside devenv shell", .{});
            qemu.addArg("-drive");
            qemu.addArg(b.fmt("if=pflash,format=raw,unit=0,readonly=on,file={s}", .{aavmf_code}));
            // create 64M empty var store
            const aa64_vars = b.addSystemCommand(&.{ "truncate", "-s", "64M" }).addOutputFileArg("aa64-vars.fd");
            qemu.addArg("-drive");
            // varstore needs to be writable on aarch64 platform, but the generated
            // blank disk will not. use snapshot instead to redirect writes to void.
            // we don't need to persist UEFI vars anyway, fake NVRAM is fine (bootloader automatically falls back to our limine)
            qemu.addPrefixedFileArg("if=pflash,format=raw,unit=1,snapshot=on,file=", aa64_vars);
        },
        .riscv64 => {
            qemu.addArgs(&.{
                "-M",
                "virt",
            });
            const riscv_code = b.graph.environ_map.get("RISCV_CODE") orelse std.debug.panic("RISCV_CODE not set - please run inside devenv shell", .{});
            qemu.addArg("-drive");
            qemu.addArg(b.fmt("if=pflash,format=raw,unit=0,readonly=on,file={s}", .{riscv_code}));
            const riscv_vars = b.graph.environ_map.get("RISCV_VARS") orelse std.debug.panic("RISCV_VARS not set - please run inside devenv shell", .{});
            qemu.addArg("-drive");
            qemu.addArg(b.fmt("if=pflash,format=raw,unit=1,snapshot=on,file={s}", .{riscv_vars}));
        },
        .x86_64 => {
            qemu.addArgs(&.{
                "-M",
                "q35",
            });
            const ovmf_code = b.graph.environ_map.get("OVMF_CODE") orelse std.debug.panic("OVMF_CODE not set - please run inside devenv shell", .{});
            qemu.addArg("-drive");
            qemu.addArg(b.fmt("if=pflash,format=raw,unit=0,readonly=on,file={s}", .{ovmf_code}));
            const ovmf_vars = b.graph.environ_map.get("OVMF_VARS") orelse std.debug.panic("OVMF_VARS not set - please run inside devenv shell", .{});
            qemu.addArg("-drive");
            qemu.addArg(b.fmt("if=pflash,format=raw,unit=1,snapshot=on,file={s}", .{ovmf_vars}));
        },
        else => std.debug.panic("Unsupported qemu arch", .{}),
    }
    // Add our os image as a drive
    qemu.addArg("-drive");
    qemu.addPrefixedFileArg("format=raw,if=virtio,file=", image);
    // redirect serial to our stdio, and run headless
    qemu.addArgs(&.{ "-m", "256M", "-serial", "stdio", "-display", "none" });

    qemu.has_side_effects = true;
    qemu.stdio = .inherit;

    const run_step = b.step("run", "Boot the kernel in QEMU");
    run_step.dependOn(&qemu.step);
}

fn getQEMUBin(arch: Arch) []const u8 {
    return switch (arch) {
        .aarch64 => "qemu-system-aarch64",
        .riscv64 => "qemu-system-riscv64",
        .x86_64 => "qemu-system-x86_64",
        else => std.debug.panic("Unsupported QEMU arch", .{}),
    };
}
