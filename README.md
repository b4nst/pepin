# pepin

> *un pépin* (French): a snag, a hitch, a minor catastrophe. also, a kernel.

A hobby OS kernel written from scratch in [Zig](https://ziglang.org), born from the entirely reasonable urge to *learn how kernels (and Zig) actually work* by reading about page tables until it physically hurt, then writing my own.

It boots. It says hello. It halts and catches fire. I'm very proud.

## what it actually does

Right now `pepin`, on three different architectures, with a straight face, can:

- get loaded by [Limine](https://limine-bootloader.org/) into the higher half ✅
- talk to a serial port (so it can say `hello from pepin` and approximately nothing else) ✅
- hand out physical memory, via a frame allocator of the dignified free-list-threaded-through-the-free-frames variety ✅
- walk and edit its *own* page tables to map memory, device MMIO included ✅

What it does **not** do (yet): processes, threads, interrupts, a filesystem, anything resembling usefulness.
It is currently a very elaborate, multi-architecture way to print one line of text.

Baby steps.

## architectures

One codebase, three boots:

| arch | how | machine | status |
|---|---|---|---|
| `x86_64` | Limine / UEFI | QEMU q35 | says hi ✅ |
| `aarch64` | Limine / UEFI | QEMU virt | says hi ✅ |
| `riscv64` | Limine / UEFI | QEMU virt | says hi ✅ |

x86 cheats: its UART is port I/O and skips the MMU entirely, so it talked early.
aarch64 and riscv refused to say a word until I'd written a working virtual-memory manager and mapped their UARTs by hand.
rude, but fair.

## building & running

You need [devenv](https://devenv.sh). It brings the whole toolbox (Zig, QEMU, Limine binaries, mtools, UEFI firmware), so you don't have to.

```sh
devenv shell                  # drops you in, with all the env vars wired up
zig build run                 # boots x86_64 in QEMU
zig build run -Darch=aarch64  # arm
zig build run -Darch=riscv64  # risc-v
```

Just want the bootable disk image without booting it?

```sh
zig build image -Darch=x86_64   # -> zig-out/os-x86_64.img
```

It runs headless (`-display none`) and pipes serial straight to your terminal, so it works perfectly fine over SSH from an iPad at 2am. Hypothetically.

## how the sausage is made

- **Zig 0.16**, freestanding, LLVM backend (the self-hosted backend and I are not currently on speaking terms regarding soft-float - it's likely me).
- **Limine boot protocol, base revision 6**: no identity map, no free 4 GiB direct map. The kernel earns every byte it touches by mapping it itself. Builds character.
- **devenv / Nix** for a hermetic toolchain, because "works on my machine" should at least be *reproducible*.
- All of the kernel code is written by a human (me). There is a literal hook that blocks my AI mentor from editing a single `.zig` file. It can review, challenge, and throw ARM reference manuals at me, but it cannot write my bugs for me. I write my own bugs, thank you very much.

## roadmap

- [x] boot
- [x] say hello
- [x] not immediately reboot (harder than it sounds)
- [x] physical + virtual memory manager, cross-arch
- [ ] exception / interrupt handlers, so a crash *tells me what it did* instead of silently rebooting like a coward
- [ ] a real console / `std.log` over serial
- [ ] processes? a scheduler? a timer interrupt? we'll see
- [ ] world domination
- [ ] (realistically) more bugs, lovingly handcrafted

## license

TBD. It's a kernel that prints "hello", calm down.
