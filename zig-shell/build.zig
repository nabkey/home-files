// build.zig - Zig Build Configuration for WASI Kernel
//
// This build script compiles the Zig shell kernel targeting wasm32-wasi.
// The output is a WebAssembly module that can be executed in a browser
// using a WASI shim (e.g., @aspect/browser_wasi_shim).

const std = @import("std");

pub fn build(b: *std.Build) void {
    // Define the target architecture: 32-bit WebAssembly with WASI system interface
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .wasi,
    });

    // Optimization strategy: ReleaseSafe for Phase 1 dev cycles
    // This retains runtime safety checks for array bounds and overflow,
    // which are essential for debugging a custom memory-managed VFS.
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSafe,
    });

    // Define the kernel executable
    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Export memory for JavaScript access
    kernel.export_memory = true;

    // Set initial memory size (2MB = 32 pages of 64KB each)
    kernel.initial_memory = 32 * 64 * 1024;

    // Allow memory growth for VFS expansion
    kernel.max_memory = 256 * 64 * 1024; // 16MB max

    // Output artifact location: zig-out/bin/kernel.wasm
    b.installArtifact(kernel);

    // Add a run step for testing (primarily for native builds during development)
    const run_cmd = b.addRunArtifact(kernel);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the kernel");
    run_step.dependOn(&run_cmd.step);

    // Add unit tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.host,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
