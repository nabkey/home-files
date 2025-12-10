// src/kernel/commands.zig - Built-in Command Implementations
//
// This module implements the built-in shell commands that interact
// directly with the VFS API. Phase 1 commands include:
// - ls: List directory contents
// - cd: Change directory
// - pwd: Print working directory
// - cat: Display file contents
// - echo: Print arguments
// - mkdir: Create directories
// - touch: Create empty files
// - clear: Clear the screen
// - help: Show help message

const std = @import("std");
const vfs = @import("../vfs/root.zig");
const VFS = vfs.VFS;
const FileType = vfs.FileType;

/// Command function signature
pub const CommandFn = *const fn (*VFS, []const []const u8, std.io.AnyWriter) anyerror!u8;

/// Command definition
pub const Command = struct {
    name: []const u8,
    func: CommandFn,
    usage: []const u8,
    description: []const u8,
};

/// List of all built-in commands
pub const builtins = [_]Command{
    .{
        .name = "ls",
        .func = cmdLs,
        .usage = "ls [path]",
        .description = "List directory contents",
    },
    .{
        .name = "cd",
        .func = cmdCd,
        .usage = "cd [path]",
        .description = "Change the current directory",
    },
    .{
        .name = "pwd",
        .func = cmdPwd,
        .usage = "pwd",
        .description = "Print the current working directory",
    },
    .{
        .name = "cat",
        .func = cmdCat,
        .usage = "cat <file>...",
        .description = "Display file contents",
    },
    .{
        .name = "echo",
        .func = cmdEcho,
        .usage = "echo [text]...",
        .description = "Display a line of text",
    },
    .{
        .name = "mkdir",
        .func = cmdMkdir,
        .usage = "mkdir [-p] <directory>...",
        .description = "Create directories",
    },
    .{
        .name = "touch",
        .func = cmdTouch,
        .usage = "touch <file>...",
        .description = "Create empty files or update timestamps",
    },
    .{
        .name = "clear",
        .func = cmdClear,
        .usage = "clear",
        .description = "Clear the terminal screen",
    },
    .{
        .name = "help",
        .func = cmdHelp,
        .usage = "help [command]",
        .description = "Display help information",
    },
    .{
        .name = "rm",
        .func = cmdRm,
        .usage = "rm <file>...",
        .description = "Remove files (directories not supported yet)",
    },
    .{
        .name = "write",
        .func = cmdWrite,
        .usage = "write <file> <content>",
        .description = "Write content to a file",
    },
};

/// Find a command by name
pub fn findCommand(name: []const u8) ?Command {
    for (builtins) |cmd| {
        if (std.mem.eql(u8, cmd.name, name)) {
            return cmd;
        }
    }
    return null;
}

// ============================================================================
// Command Implementations
// ============================================================================

/// ls - List directory contents
fn cmdLs(fs: *VFS, args: []const []const u8, writer: std.io.AnyWriter) anyerror!u8 {
    const path = if (args.len > 1) args[1] else ".";

    const entries = fs.listDirectory(path) catch |err| {
        try writer.print("ls: cannot access '{s}': {s}\n", .{ path, errorMessage(err) });
        return 1;
    };

    // Sort entries: directories first, then files, alphabetically within each group
    var dirs = std.ArrayList(*vfs.Inode).init(fs.allocator);
    defer dirs.deinit();
    var files = std.ArrayList(*vfs.Inode).init(fs.allocator);
    defer files.deinit();

    for (entries) |entry| {
        if (entry.file_type == .directory) {
            try dirs.append(entry);
        } else {
            try files.append(entry);
        }
    }

    // Print directories first
    for (dirs.items) |entry| {
        try writer.print("\x1b[1;34m{s}/\x1b[0m  ", .{entry.name});
    }

    // Print files
    for (files.items) |entry| {
        try writer.print("{s}  ", .{entry.name});
    }

    if (entries.len > 0) {
        try writer.print("\n", .{});
    }

    return 0;
}

/// cd - Change directory
fn cmdCd(fs: *VFS, args: []const []const u8, writer: std.io.AnyWriter) anyerror!u8 {
    const path = if (args.len > 1) args[1] else "/home/user";

    fs.changeDirectory(path) catch |err| {
        try writer.print("cd: {s}: {s}\n", .{ path, errorMessage(err) });
        return 1;
    };

    return 0;
}

/// pwd - Print working directory
fn cmdPwd(fs: *VFS, args: []const []const u8, writer: std.io.AnyWriter) anyerror!u8 {
    _ = args;

    const path = fs.getCurrentPath() catch |err| {
        try writer.print("pwd: error: {}\n", .{err});
        return 1;
    };
    defer fs.allocator.free(path);

    try writer.print("{s}\n", .{path});
    return 0;
}

/// cat - Display file contents
fn cmdCat(fs: *VFS, args: []const []const u8, writer: std.io.AnyWriter) anyerror!u8 {
    if (args.len < 2) {
        try writer.print("cat: missing file operand\n", .{});
        try writer.print("Usage: cat <file>...\n", .{});
        return 1;
    }

    var exit_code: u8 = 0;

    for (args[1..]) |path| {
        const content = fs.readFile(path) catch |err| {
            try writer.print("cat: {s}: {s}\n", .{ path, errorMessage(err) });
            exit_code = 1;
            continue;
        };

        try writer.print("{s}", .{content});

        // Add newline if file doesn't end with one
        if (content.len > 0 and content[content.len - 1] != '\n') {
            try writer.print("\n", .{});
        }
    }

    return exit_code;
}

/// echo - Print arguments
fn cmdEcho(fs: *VFS, args: []const []const u8, writer: std.io.AnyWriter) anyerror!u8 {
    _ = fs;

    if (args.len < 2) {
        try writer.print("\n", .{});
        return 0;
    }

    for (args[1..], 0..) |arg, i| {
        if (i > 0) {
            try writer.print(" ", .{});
        }
        try writer.print("{s}", .{arg});
    }
    try writer.print("\n", .{});

    return 0;
}

/// mkdir - Create directories
fn cmdMkdir(fs: *VFS, args: []const []const u8, writer: std.io.AnyWriter) anyerror!u8 {
    if (args.len < 2) {
        try writer.print("mkdir: missing operand\n", .{});
        try writer.print("Usage: mkdir [-p] <directory>...\n", .{});
        return 1;
    }

    var exit_code: u8 = 0;
    var create_parents = false;
    var start_idx: usize = 1;

    // Check for -p flag
    if (args.len > 1 and std.mem.eql(u8, args[1], "-p")) {
        create_parents = true;
        start_idx = 2;
    }

    if (start_idx >= args.len) {
        try writer.print("mkdir: missing operand\n", .{});
        return 1;
    }

    for (args[start_idx..]) |path| {
        if (create_parents) {
            _ = fs.createDirectoryPath(path) catch |err| {
                try writer.print("mkdir: cannot create directory '{s}': {s}\n", .{ path, errorMessage(err) });
                exit_code = 1;
            };
        } else {
            _ = fs.createDirectory(path) catch |err| {
                try writer.print("mkdir: cannot create directory '{s}': {s}\n", .{ path, errorMessage(err) });
                exit_code = 1;
            };
        }
    }

    return exit_code;
}

/// touch - Create empty files
fn cmdTouch(fs: *VFS, args: []const []const u8, writer: std.io.AnyWriter) anyerror!u8 {
    if (args.len < 2) {
        try writer.print("touch: missing file operand\n", .{});
        try writer.print("Usage: touch <file>...\n", .{});
        return 1;
    }

    var exit_code: u8 = 0;

    for (args[1..]) |path| {
        // If file exists, do nothing (timestamp update not implemented)
        if (fs.exists(path)) {
            continue;
        }

        // Create empty file
        _ = fs.createFile(path, "") catch |err| {
            try writer.print("touch: cannot touch '{s}': {s}\n", .{ path, errorMessage(err) });
            exit_code = 1;
        };
    }

    return exit_code;
}

/// clear - Clear the terminal screen
fn cmdClear(fs: *VFS, args: []const []const u8, writer: std.io.AnyWriter) anyerror!u8 {
    _ = fs;
    _ = args;

    // ANSI escape sequence to clear screen and move cursor to home
    try writer.print("\x1b[2J\x1b[H", .{});
    return 0;
}

/// help - Display help information
fn cmdHelp(fs: *VFS, args: []const []const u8, writer: std.io.AnyWriter) anyerror!u8 {
    _ = fs;

    if (args.len > 1) {
        // Show help for specific command
        const cmd_name = args[1];
        if (findCommand(cmd_name)) |cmd| {
            try writer.print("{s}\n", .{cmd.description});
            try writer.print("Usage: {s}\n", .{cmd.usage});
            return 0;
        } else {
            try writer.print("help: no help found for '{s}'\n", .{cmd_name});
            return 1;
        }
    }

    // Show help for all commands
    try writer.print("ZigShell - A browser-based shell environment\n\n", .{});
    try writer.print("Available commands:\n", .{});

    for (builtins) |cmd| {
        try writer.print("  \x1b[1m{s: <10}\x1b[0m {s}\n", .{ cmd.name, cmd.description });
    }

    try writer.print("\nType 'help <command>' for more information about a specific command.\n", .{});
    return 0;
}

/// rm - Remove files
fn cmdRm(fs: *VFS, args: []const []const u8, writer: std.io.AnyWriter) anyerror!u8 {
    _ = fs;

    if (args.len < 2) {
        try writer.print("rm: missing operand\n", .{});
        try writer.print("Usage: rm <file>...\n", .{});
        return 1;
    }

    // Phase 1: rm is not fully implemented (requires delete in VFS)
    try writer.print("rm: operation not yet implemented\n", .{});
    return 1;
}

/// write - Write content to a file
fn cmdWrite(fs: *VFS, args: []const []const u8, writer: std.io.AnyWriter) anyerror!u8 {
    if (args.len < 3) {
        try writer.print("write: missing operand\n", .{});
        try writer.print("Usage: write <file> <content>\n", .{});
        return 1;
    }

    const path = args[1];

    // Join remaining args as content
    var content = std.ArrayList(u8).init(fs.allocator);
    defer content.deinit();

    for (args[2..], 0..) |arg, i| {
        if (i > 0) {
            try content.append(' ');
        }
        try content.appendSlice(arg);
    }
    try content.append('\n');

    fs.writeFile(path, content.items) catch |err| {
        try writer.print("write: cannot write to '{s}': {s}\n", .{ path, errorMessage(err) });
        return 1;
    };

    return 0;
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Convert error to user-friendly message
fn errorMessage(err: anyerror) []const u8 {
    return switch (err) {
        vfs.FsError.FileNotFound => "No such file or directory",
        vfs.FsError.NotADirectory => "Not a directory",
        vfs.FsError.NotAFile => "Is a directory",
        vfs.FsError.FileExists => "File exists",
        vfs.FsError.DirectoryNotEmpty => "Directory not empty",
        vfs.FsError.InvalidPath => "Invalid path",
        vfs.FsError.PermissionDenied => "Permission denied",
        vfs.FsError.OutOfMemory => "Out of memory",
        else => "Unknown error",
    };
}
