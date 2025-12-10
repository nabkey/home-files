// src/kernel/entry.zig - Kernel Entry Point
//
// This module contains the main kernel initialization and run logic.

const std = @import("std");
const vfs = @import("../vfs/root.zig");
const VFS = vfs.VFS;
const Shell = @import("shell.zig").Shell;

/// Global allocator for WASI environment
/// Using GeneralPurposeAllocator for development with leak detection
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn run() !void {
    const allocator = gpa.allocator();
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
        }
    }

    // Initialize the Virtual Filesystem with bootstrapped environment
    var fs = try VFS.init(allocator);
    defer fs.deinit();

    // Initialize and run the shell
    var sh = Shell.init(allocator, &fs);
    try sh.run();
}

// Re-export modules for testing
pub const commands = @import("commands.zig");
pub const shell = @import("shell.zig");

// Tests
test "kernel initialization" {
    const allocator = std.testing.allocator;

    var fs = try VFS.init(allocator);
    defer fs.deinit();

    // Verify bootstrap created expected structure
    try std.testing.expect(fs.exists("/home/user"));
    try std.testing.expect(fs.exists("/etc/os-release"));

    const test_shell = Shell.init(allocator, &fs);
    try std.testing.expect(test_shell.isRunning());
}

test "full command execution flow" {
    const allocator = std.testing.allocator;

    var fs = try VFS.init(allocator);
    defer fs.deinit();

    var test_shell = Shell.init(allocator, &fs);

    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    // Test pwd - should be /home/user after bootstrap
    _ = try test_shell.execute("pwd", output.writer().any());
    try std.testing.expect(std.mem.indexOf(u8, output.items, "/home/user") != null);

    output.clearRetainingCapacity();

    // Test ls
    _ = try test_shell.execute("ls", output.writer().any());
    try std.testing.expect(output.items.len > 0);

    output.clearRetainingCapacity();

    // Test mkdir and cd
    _ = try test_shell.execute("mkdir testdir", output.writer().any());
    try std.testing.expect(fs.exists("testdir"));

    _ = try test_shell.execute("cd testdir", output.writer().any());
    output.clearRetainingCapacity();

    _ = try test_shell.execute("pwd", output.writer().any());
    try std.testing.expect(std.mem.indexOf(u8, output.items, "testdir") != null);
}
