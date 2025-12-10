// src/vfs/fs.zig - Filesystem Logic
//
// The FileSystem struct encapsulates the global state of the VFS,
// including the root directory and current working directory (cwd).
// It provides path resolution, file operations, and directory traversal.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Inode = @import("inode.zig").Inode;
const FileType = @import("inode.zig").FileType;

pub const FsError = error{
    FileNotFound,
    NotADirectory,
    NotAFile,
    FileExists,
    DirectoryNotEmpty,
    InvalidPath,
    PermissionDenied,
    OutOfMemory,
};

/// FileSystem manages the virtual filesystem state
pub const FileSystem = struct {
    root: *Inode,
    cwd: *Inode,
    next_inode_id: u64,
    allocator: Allocator,

    const Self = @This();

    /// Initialize a new filesystem with a root directory
    pub fn init(allocator: Allocator) !Self {
        const root = try Inode.init(allocator, 0, "/", .directory, null);

        return Self{
            .root = root,
            .cwd = root,
            .next_inode_id = 1,
            .allocator = allocator,
        };
    }

    /// Deinitialize the filesystem and free all resources
    pub fn deinit(self: *Self) void {
        self.root.deinit();
    }

    /// Generate the next unique inode ID
    fn nextId(self: *Self) u64 {
        const id = self.next_inode_id;
        self.next_inode_id += 1;
        return id;
    }

    /// Resolve a path string to an Inode
    /// Supports absolute paths (starting with /) and relative paths
    /// Handles . (current) and .. (parent) components
    pub fn resolve(self: *Self, path: []const u8) FsError!*Inode {
        if (path.len == 0) {
            return self.cwd;
        }

        var current = if (path[0] == '/') self.root else self.cwd;

        var it = std.mem.tokenizeScalar(u8, path, '/');

        while (it.next()) |component| {
            if (std.mem.eql(u8, component, ".")) {
                continue;
            }
            if (std.mem.eql(u8, component, "..")) {
                if (current.parent) |p| {
                    current = p;
                }
                continue;
            }

            if (current.file_type != .directory) {
                return FsError.NotADirectory;
            }

            if (current.findChild(component)) |child| {
                current = child;
            } else {
                return FsError.FileNotFound;
            }
        }

        return current;
    }

    /// Resolve parent directory of a path
    fn resolveParent(self: *Self, path: []const u8) FsError!struct { parent: *Inode, name: []const u8 } {
        if (path.len == 0) {
            return FsError.InvalidPath;
        }

        // Find the last path separator
        var last_sep: ?usize = null;
        for (path, 0..) |c, i| {
            if (c == '/') {
                last_sep = i;
            }
        }

        if (last_sep) |sep| {
            if (sep == 0) {
                // Path like "/filename"
                return .{
                    .parent = self.root,
                    .name = path[1..],
                };
            }
            const parent_path = path[0..sep];
            const name = path[sep + 1 ..];
            if (name.len == 0) {
                return FsError.InvalidPath;
            }
            const parent = try self.resolve(parent_path);
            return .{ .parent = parent, .name = name };
        } else {
            // Relative path with no separator
            return .{
                .parent = self.cwd,
                .name = path,
            };
        }
    }

    /// Create a new file at the given path
    pub fn createFile(self: *Self, path: []const u8, content: []const u8) FsError!*Inode {
        const result = try self.resolveParent(path);

        if (result.parent.file_type != .directory) {
            return FsError.NotADirectory;
        }

        // Check if file already exists
        if (result.parent.findChild(result.name) != null) {
            return FsError.FileExists;
        }

        const file = Inode.init(self.allocator, self.nextId(), result.name, .file, result.parent) catch {
            return FsError.OutOfMemory;
        };

        file.setContent(content) catch {
            return FsError.OutOfMemory;
        };

        result.parent.addChild(file) catch {
            return FsError.OutOfMemory;
        };

        return file;
    }

    /// Create a new directory at the given path
    pub fn createDirectory(self: *Self, path: []const u8) FsError!*Inode {
        const result = try self.resolveParent(path);

        if (result.parent.file_type != .directory) {
            return FsError.NotADirectory;
        }

        // Check if directory already exists
        if (result.parent.findChild(result.name) != null) {
            return FsError.FileExists;
        }

        const dir = Inode.init(self.allocator, self.nextId(), result.name, .directory, result.parent) catch {
            return FsError.OutOfMemory;
        };

        result.parent.addChild(dir) catch {
            return FsError.OutOfMemory;
        };

        return dir;
    }

    /// Create a directory and all parent directories as needed (like mkdir -p)
    pub fn createDirectoryPath(self: *Self, path: []const u8) FsError!*Inode {
        var current = if (path.len > 0 and path[0] == '/') self.root else self.cwd;

        var it = std.mem.tokenizeScalar(u8, path, '/');

        while (it.next()) |component| {
            if (std.mem.eql(u8, component, ".")) {
                continue;
            }
            if (std.mem.eql(u8, component, "..")) {
                if (current.parent) |p| {
                    current = p;
                }
                continue;
            }

            if (current.findChild(component)) |child| {
                if (child.file_type != .directory) {
                    return FsError.NotADirectory;
                }
                current = child;
            } else {
                // Create the directory
                const dir = Inode.init(self.allocator, self.nextId(), component, .directory, current) catch {
                    return FsError.OutOfMemory;
                };
                current.addChild(dir) catch {
                    return FsError.OutOfMemory;
                };
                current = dir;
            }
        }

        return current;
    }

    /// Read the content of a file
    pub fn readFile(self: *Self, path: []const u8) FsError![]const u8 {
        const inode = try self.resolve(path);

        if (inode.file_type != .file) {
            return FsError.NotAFile;
        }

        return inode.getContent() catch FsError.NotAFile;
    }

    /// Write content to a file (overwrites existing content)
    pub fn writeFile(self: *Self, path: []const u8, content: []const u8) FsError!void {
        const inode = self.resolve(path) catch |err| {
            if (err == FsError.FileNotFound) {
                // Create the file if it doesn't exist
                _ = try self.createFile(path, content);
                return;
            }
            return err;
        };

        if (inode.file_type != .file) {
            return FsError.NotAFile;
        }

        inode.setContent(content) catch {
            return FsError.OutOfMemory;
        };
    }

    /// Append content to a file
    pub fn appendFile(self: *Self, path: []const u8, content: []const u8) FsError!void {
        const inode = try self.resolve(path);

        if (inode.file_type != .file) {
            return FsError.NotAFile;
        }

        inode.appendContent(content) catch {
            return FsError.OutOfMemory;
        };
    }

    /// List contents of a directory
    pub fn listDirectory(self: *Self, path: []const u8) FsError![]*Inode {
        const inode = try self.resolve(path);

        if (inode.file_type != .directory) {
            return FsError.NotADirectory;
        }

        return inode.getChildren() catch FsError.NotADirectory;
    }

    /// Change the current working directory
    pub fn changeDirectory(self: *Self, path: []const u8) FsError!void {
        const inode = try self.resolve(path);

        if (inode.file_type != .directory) {
            return FsError.NotADirectory;
        }

        self.cwd = inode;
    }

    /// Get the current working directory path
    pub fn getCurrentPath(self: *Self) ![]u8 {
        return self.cwd.getPath(self.allocator);
    }

    /// Check if a path exists
    pub fn exists(self: *Self, path: []const u8) bool {
        _ = self.resolve(path) catch return false;
        return true;
    }

    /// Check if a path is a directory
    pub fn isDirectory(self: *Self, path: []const u8) bool {
        const inode = self.resolve(path) catch return false;
        return inode.file_type == .directory;
    }

    /// Check if a path is a file
    pub fn isFile(self: *Self, path: []const u8) bool {
        const inode = self.resolve(path) catch return false;
        return inode.file_type == .file;
    }
};

// Tests
test "filesystem init and deinit" {
    const allocator = std.testing.allocator;

    var fs = try FileSystem.init(allocator);
    defer fs.deinit();

    try std.testing.expect(fs.root == fs.cwd);
    try std.testing.expectEqual(@as(u64, 1), fs.next_inode_id);
}

test "path resolution" {
    const allocator = std.testing.allocator;

    var fs = try FileSystem.init(allocator);
    defer fs.deinit();

    // Create some directories
    _ = try fs.createDirectory("/home");
    _ = try fs.createDirectory("/home/user");

    // Resolve absolute path
    const home = try fs.resolve("/home");
    try std.testing.expectEqualStrings("home", home.name);

    // Resolve relative path after cd
    try fs.changeDirectory("/home");
    const user = try fs.resolve("user");
    try std.testing.expectEqualStrings("user", user.name);

    // Test .. navigation
    try fs.changeDirectory("/home/user");
    const parent = try fs.resolve("..");
    try std.testing.expectEqualStrings("home", parent.name);
}

test "file operations" {
    const allocator = std.testing.allocator;

    var fs = try FileSystem.init(allocator);
    defer fs.deinit();

    // Create a file
    _ = try fs.createFile("/test.txt", "Hello, World!");

    // Read the file
    const content = try fs.readFile("/test.txt");
    try std.testing.expectEqualStrings("Hello, World!", content);

    // Write to the file
    try fs.writeFile("/test.txt", "New content");
    const updated = try fs.readFile("/test.txt");
    try std.testing.expectEqualStrings("New content", updated);

    // Append to the file
    try fs.appendFile("/test.txt", " appended");
    const appended = try fs.readFile("/test.txt");
    try std.testing.expectEqualStrings("New content appended", appended);
}

test "directory operations" {
    const allocator = std.testing.allocator;

    var fs = try FileSystem.init(allocator);
    defer fs.deinit();

    // Create nested directories with mkdir -p equivalent
    _ = try fs.createDirectoryPath("/a/b/c");

    // Verify the path exists
    try std.testing.expect(fs.exists("/a/b/c"));
    try std.testing.expect(fs.isDirectory("/a/b/c"));

    // List directory contents
    _ = try fs.createFile("/a/file.txt", "test");
    const entries = try fs.listDirectory("/a");
    try std.testing.expectEqual(@as(usize, 2), entries.len);
}
