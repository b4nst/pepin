{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

let
  # Limine's nixpkgs package is darwin-unsupported (it builds the EFI binaries
  # from source). We don't need to build them: the binary branch ships prebuilt,
  # host-independent BOOT*.EFI for every target arch. Pinned to a release tag.
  limine-bin = pkgs.fetchFromGitHub {
    owner = "limine-bootloader";
    repo = "limine";
    rev = "v11.4.1-binary";
    hash = "sha256-lBPx5B3yiuWC+CiaygsOwCWKTEnLU2Wv/DE+msGXM6w=";
  };
in
{
  # https://devenv.sh/basics/
  env.GREET = "pepin's devenv";

  # https://devenv.sh/packages/
  packages = [
    pkgs.git
    pkgs.jq # used by the Claude Code guardrail hook below
    pkgs.qemu
    pkgs.mtools # build the FAT ESP image without mounting (macOS-safe)
  ];

  # Paths exposed to build.zig (read with std.process.getEnvVarOwned).
  # LIMINE_DIR holds the per-target BOOT*.EFI; build.zig picks the right one.
  # Firmware comes from QEMU's own bundle (pkgs.OVMF is unsupported on darwin),
  # which conveniently ships every arch, so cross-arch boot is covered.
  env.LIMINE_DIR = "${limine-bin}";
  env.OVMF_CODE = "${pkgs.qemu}/share/qemu/edk2-x86_64-code.fd";
  env.OVMF_VARS = "${pkgs.qemu}/share/qemu/edk2-i386-vars.fd"; # vars store is shared, named i386
  env.AAVMF_CODE = "${pkgs.qemu}/share/qemu/edk2-aarch64-code.fd";
  env.RISCV_CODE = "${pkgs.qemu}/share/qemu/edk2-riscv-code.fd";
  env.RISCV_VARS = "${pkgs.qemu}/share/qemu/edk2-riscv-vars.fd"; # riscv ships its own vars, unlike aarch64

  # https://devenv.sh/languages/
  languages.zig.enable = true;

  # https://devenv.sh/integrations/claude-code/
  claude.code.enable = true;

  # Guardrail: this is a learning project. The kernel code is written by the
  # human only. Claude acts as a mentor (review, challenge, reading material)
  # and is hard-blocked from writing any kernel build/source file.
  claude.code.hooks.block-kernel-writes = {
    enable = true;
    name = "Block Claude from writing kernel code";
    hookType = "PreToolUse";
    matcher = "^(Edit|MultiEdit|Write)$";
    command = ''
      json=$(cat)
      file_path=$(echo "$json" | jq -r '.tool_input.file_path // .file_path // empty')

      # Zig sources, build manifest, assembly, and linker scripts are off-limits.
      if [[ "$file_path" =~ \.(zig|zon|S|s|asm|ld|lds)$ ]]; then
        echo "Blocked: '$file_path' is kernel code. This is a learning project - only the human writes kernel code." >&2
        echo "Claude's job here is to mentor: review, challenge, and point to reading material." >&2
        exit 2 # exit 2 = blocking error in Claude Code's hook protocol; stderr is fed back to Claude
      fi
      exit 0
    '';
  };

  # https://devenv.sh/integrations/claude-code/#agents
  claude.code.agents.mentor = {
    description = "Kernel & Zig mentor. Reviews the human's code, challenges design decisions, and supplies reading material. Never writes code.";
    proactive = true;
    tools = [
      "Read"
      "Grep"
      "Glob"
      "WebFetch"
      "WebSearch"
    ];
    prompt = ''
      You are a mentor for someone learning Zig and Linux kernel development by
      building a kernel from scratch. Your role is strictly pedagogical.

      Hard rules:
      - NEVER write, edit, or dictate kernel code. No code snippets that can be
        pasted in as a solution. The learner writes 100% of the kernel.
      - Prefer the Socratic method: ask questions that lead them to the answer.
      - When they are stuck, give a hint or the relevant concept/keyword, not the
        solution. Escalate detail only if they remain stuck after trying.

      What you do:
      - Review their Zig for correctness, idioms, memory/comptime usage, and
        kernel-specific pitfalls (freestanding target, no libc, alignment, MMIO,
        volatile, calling conventions, linker layout).
      - Challenge design decisions: ask "why this approach?", surface trade-offs,
        point out assumptions, and name failure modes they haven't considered.
      - Provide reading material: link to authoritative sources (Zig language
        reference, OSDev wiki, Intel/ARM manuals, Linux source, relevant papers).
      - Connect what they're doing to how the real Linux kernel does it.

      Keep feedback concrete and tied to their actual code (cite file:line).
    '';
  };

  # https://devenv.sh/integrations/claude-code/#commands
  claude.code.commands = {
    explain-concept = ''
      Explain a Zig or kernel concept from first principles for a learner.

      Ask clarifying questions if the concept name is ambiguous. Build intuition
      before formalism, use analogies, and finish with 1-3 authoritative links
      for deeper reading. Do NOT write kernel code - illustrate with minimal,
      non-kernel pseudocode only if it genuinely aids understanding.
    '';
    review-my-code = ''
      Review the kernel code I just wrote as a mentor, not a fixer.

      Read the current diff (`git diff`) or the file I point to. Flag correctness
      bugs, non-idiomatic Zig, and kernel pitfalls (freestanding/no-libc,
      alignment, volatile/MMIO, calling conventions, linker layout). For each
      issue, explain WHY it is wrong and what to read - do not paste a fix.
    '';
    challenge-me = ''
      Challenge my current design decision like a skeptical senior engineer.

      Pick the most important design choice in my recent work, then probe it:
      "why this and not X?", surface trade-offs, name failure modes and edge
      cases I likely haven't handled, and compare to how Linux does it. End with
      one question I should be able to answer before moving on.
    '';
    reading = ''
      Recommend reading material for what I'm currently working on.

      Infer the topic from recent context or ask. Return a short, ordered list
      of authoritative sources (Zig reference, OSDev wiki, architecture manuals,
      Linux source files, papers) with a one-line note on why each matters and
      what to focus on.
    '';
  };

  # https://devenv.sh/processes/
  # processes.dev.exec = "${lib.getExe pkgs.watchexec} -n -- ls -la";

  # https://devenv.sh/services/
  # services.postgres.enable = true;

  # https://devenv.sh/scripts/
  scripts.hello.exec = ''
    echo hello from $GREET
  '';

  # https://devenv.sh/basics/
  enterShell = ''
    hello         # Run scripts directly
    git --version # Use packages
  '';

  # https://devenv.sh/tasks/
  # tasks = {
  #   "myproj:setup".exec = "mytool build";
  #   "devenv:enterShell".after = [ "myproj:setup" ];
  # };

  # https://devenv.sh/tests/
  enterTest = ''
    echo "Running tests"
    git --version | grep --color=auto "${pkgs.git.version}"
  '';

  # https://devenv.sh/git-hooks/
  # git-hooks.hooks.shellcheck.enable = true;

  # See full reference at https://devenv.sh/reference/options/
}
