// src/vfs/root.zig - VFS Public API
//
// This module provides the public interface for the Virtual Filesystem.
// It re-exports the core types and provides a bootstrap function to
// initialize the VFS with a default directory structure.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Inode = @import("inode.zig").Inode;
pub const FileType = @import("inode.zig").FileType;
pub const FileSystem = @import("fs.zig").FileSystem;
pub const FsError = @import("fs.zig").FsError;

/// VFS instance with bootstrapped environment
pub const VFS = struct {
    fs: FileSystem,
    allocator: Allocator,

    const Self = @This();

    /// Initialize a new VFS with a bootstrapped filesystem
    pub fn init(allocator: Allocator) !Self {
        var fs = try FileSystem.init(allocator);
        errdefer fs.deinit();

        // Bootstrap the default directory structure
        try bootstrap(&fs);

        return Self{
            .fs = fs,
            .allocator = allocator,
        };
    }

    /// Deinitialize the VFS
    pub fn deinit(self: *Self) void {
        self.fs.deinit();
    }

    // Delegate filesystem operations to the underlying FileSystem

    pub fn resolve(self: *Self, path: []const u8) FsError!*Inode {
        return self.fs.resolve(path);
    }

    pub fn createFile(self: *Self, path: []const u8, content: []const u8) FsError!*Inode {
        return self.fs.createFile(path, content);
    }

    pub fn createDirectory(self: *Self, path: []const u8) FsError!*Inode {
        return self.fs.createDirectory(path);
    }

    pub fn createDirectoryPath(self: *Self, path: []const u8) FsError!*Inode {
        return self.fs.createDirectoryPath(path);
    }

    pub fn readFile(self: *Self, path: []const u8) FsError![]const u8 {
        return self.fs.readFile(path);
    }

    pub fn writeFile(self: *Self, path: []const u8, content: []const u8) FsError!void {
        return self.fs.writeFile(path, content);
    }

    pub fn appendFile(self: *Self, path: []const u8, content: []const u8) FsError!void {
        return self.fs.appendFile(path, content);
    }

    pub fn listDirectory(self: *Self, path: []const u8) FsError![]*Inode {
        return self.fs.listDirectory(path);
    }

    pub fn changeDirectory(self: *Self, path: []const u8) FsError!void {
        return self.fs.changeDirectory(path);
    }

    pub fn getCurrentPath(self: *Self) ![]u8 {
        return self.fs.getCurrentPath();
    }

    pub fn exists(self: *Self, path: []const u8) bool {
        return self.fs.exists(path);
    }

    pub fn isDirectory(self: *Self, path: []const u8) bool {
        return self.fs.isDirectory(path);
    }

    pub fn isFile(self: *Self, path: []const u8) bool {
        return self.fs.isFile(path);
    }

    /// Get the current working directory inode
    pub fn getCwd(self: *Self) *Inode {
        return self.fs.cwd;
    }

    /// Get the root inode
    pub fn getRoot(self: *Self) *Inode {
        return self.fs.root;
    }
};

/// Bootstrap the filesystem with a default directory structure
fn bootstrap(fs: *FileSystem) !void {
    // Create standard Unix-like directory structure

    // /bin - Placeholder for executables (future use)
    _ = try fs.createDirectory("/bin");

    // /etc - Configuration files
    _ = try fs.createDirectory("/etc");

    // /home - User home directories
    _ = try fs.createDirectory("/home");

    // /home/user - Default user home
    _ = try fs.createDirectory("/home/user");

    // /tmp - Temporary files
    _ = try fs.createDirectory("/tmp");

    // /var - Variable data
    _ = try fs.createDirectory("/var");
    _ = try fs.createDirectory("/var/log");

    // Create some default files

    // /etc/os-release - System information
    _ = try fs.createFile("/etc/os-release",
        \\NAME="ZigShell"
        \\VERSION="1.0.0"
        \\ID=zigshell
        \\PRETTY_NAME="ZigShell WASI Environment"
        \\HOME_URL="https://github.com/nabkey/home-files"
        \\
    );

    // /etc/passwd - Simulated user database
    _ = try fs.createFile("/etc/passwd",
        \\root:x:0:0:root:/root:/bin/sh
        \\user:x:1000:1000:user:/home/user:/bin/sh
        \\
    );

    // /etc/hostname
    _ = try fs.createFile("/etc/hostname", "zigshell\n");

    // /home/user/.profile - User profile script
    _ = try fs.createFile("/home/user/.profile",
        \\# ZigShell Profile
        \\export USER=user
        \\export HOME=/home/user
        \\export PATH=/bin
        \\export PS1="$ "
        \\
    );

    // /home/user/README.txt - Welcome file
    _ = try fs.createFile("/home/user/README.txt",
        \\Welcome to ZigShell!
        \\
        \\This is a browser-based shell environment powered by Zig and WebAssembly.
        \\
        \\Available commands:
        \\  ls      - List directory contents
        \\  cd      - Change directory
        \\  pwd     - Print working directory
        \\  cat     - Display file contents
        \\  echo    - Print arguments
        \\  mkdir   - Create directories
        \\  touch   - Create empty files
        \\  clear   - Clear the screen
        \\  help    - Show this help message
        \\
        \\Try exploring the filesystem with 'ls /' to see the directory structure.
        \\
    );

    // Set the initial working directory to /home/user
    try fs.changeDirectory("/home/user");
}

// Tests
test "VFS initialization and bootstrap" {
    const allocator = std.testing.allocator;

    var vfs = try VFS.init(allocator);
    defer vfs.deinit();

    // Check that bootstrap created expected directories
    try std.testing.expect(vfs.exists("/bin"));
    try std.testing.expect(vfs.exists("/etc"));
    try std.testing.expect(vfs.exists("/home"));
    try std.testing.expect(vfs.exists("/home/user"));
    try std.testing.expect(vfs.exists("/tmp"));

    // Check that bootstrap created expected files
    try std.testing.expect(vfs.isFile("/etc/os-release"));
    try std.testing.expect(vfs.isFile("/etc/hostname"));
    try std.testing.expect(vfs.isFile("/home/user/README.txt"));

    // Check initial CWD is /home/user
    const cwd = try vfs.getCurrentPath();
    defer vfs.allocator.free(cwd);
    try std.testing.expectEqualStrings("/home/user", cwd);
}

test "VFS file operations" {
    const allocator = std.testing.allocator;

    var vfs = try VFS.init(allocator);
    defer vfs.deinit();

    // Create a new file in the home directory
    _ = try vfs.createFile("test.txt", "Test content");

    // Read it back
    const content = try vfs.readFile("test.txt");
    try std.testing.expectEqualStrings("Test content", content);

    // Read a bootstrapped file
    const hostname = try vfs.readFile("/etc/hostname");
    try std.testing.expectEqualStrings("zigshell\n", hostname);
}
