// src/kernel/shell.zig - REPL Loop & State Machine
//
// This module implements the shell's Read-Eval-Print Loop (REPL).
// It handles:
// - Prompt generation
// - Input reading
// - Command dispatching
// - Exit handling

const std = @import("std");
const vfs = @import("../vfs/root.zig");
const VFS = vfs.VFS;
const commands = @import("commands.zig");
const tokenizer = @import("../utils/tokenizer.zig");

/// Shell state
pub const Shell = struct {
    vfs: *VFS,
    running: bool,
    last_exit_code: u8,
    allocator: std.mem.Allocator,
    username: []const u8,
    hostname: []const u8,

    const Self = @This();

    /// Initialize a new shell instance
    pub fn init(allocator: std.mem.Allocator, fs: *VFS) Self {
        return Self{
            .vfs = fs,
            .running = true,
            .last_exit_code = 0,
            .allocator = allocator,
            .username = "user",
            .hostname = "zigshell",
        };
    }

    /// Run the shell's main REPL loop
    pub fn run(self: *Self) !void {
        const stdin = std.io.getStdIn().reader();
        const stdout = std.io.getStdOut().writer();
        const any_stdout = stdout.any();

        // Print welcome message
        try stdout.print("\x1b[1;32mZigShell v1.0.0\x1b[0m - Type 'help' for available commands\n\n", .{});

        // Command line buffer
        var buffer: [4096]u8 = undefined;

        while (self.running) {
            // Generate and print prompt
            try self.printPrompt(stdout);

            // Read input line
            const line = stdin.readUntilDelimiterOrEof(&buffer, '\n') catch |err| {
                try stdout.print("\nError reading input: {}\n", .{err});
                continue;
            };

            if (line) |input| {
                // Trim whitespace
                const trimmed = std.mem.trim(u8, input, " \t\r\n");

                if (trimmed.len == 0) {
                    continue;
                }

                // Execute the command
                self.last_exit_code = try self.execute(trimmed, any_stdout);
            } else {
                // EOF received
                try stdout.print("\nexit\n", .{});
                self.running = false;
            }
        }
    }

    /// Print the shell prompt
    fn printPrompt(self: *Self, writer: anytype) !void {
        // Get current path
        const cwd_path = self.vfs.getCurrentPath() catch "/";
        defer if (!std.mem.eql(u8, cwd_path, "/")) self.allocator.free(cwd_path);

        // Shorten home directory to ~
        var display_path: []const u8 = cwd_path;
        if (std.mem.startsWith(u8, cwd_path, "/home/user")) {
            if (cwd_path.len == 10) {
                display_path = "~";
            } else if (cwd_path.len > 10) {
                // Create ~suffix path
                const suffix = cwd_path[10..];
                var path_buf: [256]u8 = undefined;
                const formatted = std.fmt.bufPrint(&path_buf, "~{s}", .{suffix}) catch cwd_path;
                display_path = formatted;
            }
        }

        // Color prompt based on last exit code
        const prompt_color = if (self.last_exit_code == 0) "\x1b[1;32m" else "\x1b[1;31m";

        // Print prompt: user@hostname:path$
        try writer.print("\x1b[1;36m{s}\x1b[0m@\x1b[1;35m{s}\x1b[0m:\x1b[1;34m{s}\x1b[0m{s}$\x1b[0m ", .{
            self.username,
            self.hostname,
            display_path,
            prompt_color,
        });
    }

    /// Execute a command line
    pub fn execute(self: *Self, input: []const u8, writer: std.io.AnyWriter) !u8 {
        // Parse the command line
        var tok = tokenizer.Tokenizer.init(self.allocator);
        defer tok.deinit();

        const tokens = tok.tokenize(input) catch |err| {
            switch (err) {
                tokenizer.TokenError.UnterminatedQuote => {
                    try writer.print("syntax error: unterminated quote\n", .{});
                },
                tokenizer.TokenError.OutOfMemory => {
                    try writer.print("error: out of memory\n", .{});
                },
                else => {
                    try writer.print("syntax error\n", .{});
                },
            }
            return 1;
        };

        if (tokens.len == 0) {
            return 0;
        }

        const cmd_name = tokens[0];

        // Check for built-in exit command
        if (std.mem.eql(u8, cmd_name, "exit")) {
            return self.cmdExit(tokens, writer);
        }

        // Convert tokens to const slices for command functions
        var const_tokens = try self.allocator.alloc([]const u8, tokens.len);
        defer self.allocator.free(const_tokens);
        for (tokens, 0..) |token, i| {
            const_tokens[i] = token;
        }

        // Find and execute command
        if (commands.findCommand(cmd_name)) |cmd| {
            return cmd.func(self.vfs, const_tokens, writer) catch |err| {
                try writer.print("{s}: error: {}\n", .{ cmd_name, err });
                return 1;
            };
        } else {
            try writer.print("{s}: command not found\n", .{cmd_name});
            return 127;
        }
    }

    /// Handle the exit command
    fn cmdExit(self: *Self, args: [][]u8, writer: std.io.AnyWriter) !u8 {
        var exit_code: u8 = 0;

        if (args.len > 1) {
            exit_code = std.fmt.parseInt(u8, args[1], 10) catch {
                try writer.print("exit: numeric argument required\n", .{});
                exit_code = 2;
            };
        }

        self.running = false;
        return exit_code;
    }

    /// Check if the shell is still running
    pub fn isRunning(self: *Self) bool {
        return self.running;
    }

    /// Stop the shell
    pub fn stop(self: *Self) void {
        self.running = false;
    }
};

// Tests
test "shell initialization" {
    const allocator = std.testing.allocator;

    var fs = try VFS.init(allocator);
    defer fs.deinit();

    const shell = Shell.init(allocator, &fs);
    try std.testing.expect(shell.running);
    try std.testing.expectEqual(@as(u8, 0), shell.last_exit_code);
}

test "command execution" {
    const allocator = std.testing.allocator;

    var fs = try VFS.init(allocator);
    defer fs.deinit();

    var shell = Shell.init(allocator, &fs);

    // Test echo command
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    const exit_code = try shell.execute("echo hello world", output.writer().any());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expectEqualStrings("hello world\n", output.items);
}

test "command not found" {
    const allocator = std.testing.allocator;

    var fs = try VFS.init(allocator);
    defer fs.deinit();

    var shell = Shell.init(allocator, &fs);

    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    const exit_code = try shell.execute("nonexistent", output.writer().any());
    try std.testing.expectEqual(@as(u8, 127), exit_code);
}
