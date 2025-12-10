// src/vfs/inode.zig - Inode Data Structures
//
// The Virtual Filesystem uses a simplified Unix-style inode architecture.
// This separates the metadata of a file (permissions, type, size) from its
// identity (inode ID) and its data (content).

const std = @import("std");
const Allocator = std.mem.Allocator;

/// File types supported by the VFS
pub const FileType = enum {
    file,
    directory,
    symlink, // Reserved for Phase 2
};

/// Inode represents a file or directory in the virtual filesystem
pub const Inode = struct {
    id: u64,
    file_type: FileType,
    mode: u32, // Permissions (simulated 0o755 for dirs, 0o644 for files)
    name: []u8, // Filename (owned slice)

    // Union for type-specific data to save memory
    data: union(enum) {
        content: std.ArrayList(u8), // For Files: Byte content
        children: std.ArrayList(*Inode), // For Dirs: List of pointers to children
        target: []u8, // For Symlinks: Target path (Phase 2)
    },

    parent: ?*Inode, // Back-pointer for ".." traversal

    allocator: Allocator,

    const Self = @This();

    /// Initialize a new Inode
    pub fn init(
        allocator: Allocator,
        id: u64,
        name: []const u8,
        file_type: FileType,
        parent: ?*Inode,
    ) !*Self {
        const node = try allocator.create(Inode);
        errdefer allocator.destroy(node);

        node.id = id;
        node.file_type = file_type;
        node.mode = if (file_type == .directory) 0o755 else 0o644;
        node.name = try allocator.dupe(u8, name);
        node.parent = parent;
        node.allocator = allocator;

        switch (file_type) {
            .file => {
                node.data = .{ .content = std.ArrayList(u8).init(allocator) };
            },
            .directory => {
                node.data = .{ .children = std.ArrayList(*Inode).init(allocator) };
            },
            .symlink => {
                // Reserved for Phase 2
                node.data = .{ .target = try allocator.dupe(u8, "") };
            },
        }

        return node;
    }

    /// Deinitialize and free the Inode
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.name);
        switch (self.data) {
            .content => |*content| content.deinit(),
            .children => |*children| {
                // Recursively deinit all children
                for (children.items) |child| {
                    child.deinit();
                }
                children.deinit();
            },
            .target => |target| self.allocator.free(target),
        }
        self.allocator.destroy(self);
    }

    /// Add a child to a directory inode
    pub fn addChild(self: *Self, child: *Inode) !void {
        if (self.file_type != .directory) {
            return error.NotADirectory;
        }
        try self.data.children.append(child);
    }

    /// Find a child by name in a directory
    pub fn findChild(self: *Self, name: []const u8) ?*Inode {
        if (self.file_type != .directory) {
            return null;
        }
        for (self.data.children.items) |child| {
            if (std.mem.eql(u8, child.name, name)) {
                return child;
            }
        }
        return null;
    }

    /// Get the content of a file inode
    pub fn getContent(self: *Self) ![]const u8 {
        if (self.file_type != .file) {
            return error.NotAFile;
        }
        return self.data.content.items;
    }

    /// Set the content of a file inode
    pub fn setContent(self: *Self, content: []const u8) !void {
        if (self.file_type != .file) {
            return error.NotAFile;
        }
        self.data.content.clearRetainingCapacity();
        try self.data.content.appendSlice(content);
    }

    /// Append content to a file inode
    pub fn appendContent(self: *Self, content: []const u8) !void {
        if (self.file_type != .file) {
            return error.NotAFile;
        }
        try self.data.content.appendSlice(content);
    }

    /// Get the children of a directory inode
    pub fn getChildren(self: *Self) ![]*Inode {
        if (self.file_type != .directory) {
            return error.NotADirectory;
        }
        return self.data.children.items;
    }

    /// Get the full path of this inode
    pub fn getPath(self: *Self, allocator: Allocator) ![]u8 {
        var components = std.ArrayList([]const u8).init(allocator);
        defer components.deinit();

        var current: ?*Inode = self;
        while (current) |node| {
            if (node.parent == null) {
                // Root node
                break;
            }
            try components.insert(0, node.name);
            current = node.parent;
        }

        if (components.items.len == 0) {
            return try allocator.dupe(u8, "/");
        }

        var total_len: usize = 1; // Leading slash
        for (components.items) |component| {
            total_len += component.len + 1; // component + slash
        }

        var result = try allocator.alloc(u8, total_len - 1); // Minus trailing slash
        var pos: usize = 0;

        for (components.items) |component| {
            result[pos] = '/';
            pos += 1;
            @memcpy(result[pos .. pos + component.len], component);
            pos += component.len;
        }

        return result;
    }

    /// Check if this inode is the root
    pub fn isRoot(self: *Self) bool {
        return self.parent == null;
    }

    /// Get file size (for files, content length; for directories, child count)
    pub fn getSize(self: *Self) usize {
        return switch (self.data) {
            .content => |content| content.items.len,
            .children => |children| children.items.len,
            .target => |target| target.len,
        };
    }
};

// Tests
test "inode creation and deletion" {
    const allocator = std.testing.allocator;

    const root = try Inode.init(allocator, 0, "/", .directory, null);
    defer root.deinit();

    try std.testing.expectEqual(@as(u64, 0), root.id);
    try std.testing.expectEqual(FileType.directory, root.file_type);
    try std.testing.expect(root.isRoot());
}

test "file content manipulation" {
    const allocator = std.testing.allocator;

    const root = try Inode.init(allocator, 0, "/", .directory, null);
    defer root.deinit();

    const file = try Inode.init(allocator, 1, "test.txt", .file, root);
    try root.addChild(file);

    try file.setContent("Hello, World!");
    const content = try file.getContent();
    try std.testing.expectEqualStrings("Hello, World!", content);

    try file.appendContent(" More content.");
    const updated = try file.getContent();
    try std.testing.expectEqualStrings("Hello, World! More content.", updated);
}

test "directory child operations" {
    const allocator = std.testing.allocator;

    const root = try Inode.init(allocator, 0, "/", .directory, null);
    defer root.deinit();

    const child1 = try Inode.init(allocator, 1, "dir1", .directory, root);
    const child2 = try Inode.init(allocator, 2, "file1.txt", .file, root);

    try root.addChild(child1);
    try root.addChild(child2);

    const found = root.findChild("dir1");
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("dir1", found.?.name);

    const not_found = root.findChild("nonexistent");
    try std.testing.expect(not_found == null);
}
