// src/main.zig - Root Module Entry Point
//
// This is the main entry point for the ZigShell WASI kernel.
// It serves as the module root, allowing proper imports across the project.

const std = @import("std");

// Re-export all modules from the root
pub const vfs = @import("vfs/root.zig");
pub const kernel = @import("kernel/entry.zig");
pub const utils = @import("utils/tokenizer.zig");

// Main entry point delegates to kernel
pub fn main() !void {
    try kernel.run();
}
