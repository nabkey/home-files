// src/utils/tokenizer.zig - Command Line Parsing Logic
//
// This module provides tokenization and parsing utilities for shell commands.
// It handles:
// - Word splitting (by whitespace)
// - Quote handling (single and double quotes)
// - Escape sequences
// - Basic argument parsing

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const TokenError = error{
    UnterminatedQuote,
    UnterminatedEscape,
    InvalidEscapeSequence,
    OutOfMemory,
    BufferOverflow,
};

/// Token types for future expansion (pipes, redirects, etc.)
pub const TokenType = enum {
    word, // Regular word/argument
    pipe, // | (Phase 2)
    redirect_in, // < (Phase 2)
    redirect_out, // > (Phase 2)
    redirect_append, // >> (Phase 2)
    semicolon, // ; (Phase 2)
    ampersand, // & (Phase 2)
    newline, // End of line
};

/// A single token from the command line
pub const Token = struct {
    token_type: TokenType,
    value: []const u8,
};

/// Tokenizer for shell command lines
pub const Tokenizer = struct {
    allocator: Allocator,
    tokens: std.ArrayList([]u8),
    input: []const u8,
    pos: usize,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .tokens = std.ArrayList([]u8).init(allocator),
            .input = "",
            .pos = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.tokens.items) |token| {
            self.allocator.free(token);
        }
        self.tokens.deinit();
    }

    /// Reset the tokenizer for a new input
    pub fn reset(self: *Self) void {
        for (self.tokens.items) |token| {
            self.allocator.free(token);
        }
        self.tokens.clearRetainingCapacity();
        self.input = "";
        self.pos = 0;
    }

    /// Tokenize a command line string
    pub fn tokenize(self: *Self, input: []const u8) TokenError![][]u8 {
        self.reset();
        self.input = input;
        self.pos = 0;

        while (self.pos < self.input.len) {
            // Skip leading whitespace
            self.skipWhitespace();

            if (self.pos >= self.input.len) {
                break;
            }

            // Parse the next token
            const token = try self.parseToken();
            if (token.len > 0) {
                self.tokens.append(token) catch return TokenError.OutOfMemory;
            }
        }

        return self.tokens.items;
    }

    /// Skip whitespace characters
    fn skipWhitespace(self: *Self) void {
        while (self.pos < self.input.len and isWhitespace(self.input[self.pos])) {
            self.pos += 1;
        }
    }

    /// Parse a single token (word, quoted string, etc.)
    fn parseToken(self: *Self) TokenError![]u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        errdefer buffer.deinit();

        const c = self.input[self.pos];

        // Handle quoted strings
        if (c == '"' or c == '\'') {
            try self.parseQuotedString(&buffer, c);
        } else {
            // Regular word
            try self.parseWord(&buffer);
        }

        return buffer.toOwnedSlice() catch return TokenError.OutOfMemory;
    }

    /// Parse a quoted string
    fn parseQuotedString(self: *Self, buffer: *std.ArrayList(u8), quote_char: u8) TokenError!void {
        self.pos += 1; // Skip opening quote

        while (self.pos < self.input.len) {
            const c = self.input[self.pos];

            if (c == quote_char) {
                self.pos += 1; // Skip closing quote
                // Continue parsing if there's more after the quote (no space)
                if (self.pos < self.input.len and !isWhitespace(self.input[self.pos])) {
                    if (self.input[self.pos] == '"' or self.input[self.pos] == '\'') {
                        try self.parseQuotedString(buffer, self.input[self.pos]);
                    } else {
                        try self.parseWord(buffer);
                    }
                }
                return;
            }

            // Handle escape sequences in double quotes
            if (quote_char == '"' and c == '\\' and self.pos + 1 < self.input.len) {
                const next = self.input[self.pos + 1];
                if (next == '"' or next == '\\' or next == '$' or next == '`' or next == '\n') {
                    buffer.append(next) catch return TokenError.OutOfMemory;
                    self.pos += 2;
                    continue;
                }
            }

            buffer.append(c) catch return TokenError.OutOfMemory;
            self.pos += 1;
        }

        // Reached end of input without closing quote
        return TokenError.UnterminatedQuote;
    }

    /// Parse an unquoted word
    fn parseWord(self: *Self, buffer: *std.ArrayList(u8)) TokenError!void {
        while (self.pos < self.input.len) {
            const c = self.input[self.pos];

            // Stop at whitespace
            if (isWhitespace(c)) {
                break;
            }

            // Handle escape sequences
            if (c == '\\' and self.pos + 1 < self.input.len) {
                self.pos += 1;
                buffer.append(self.input[self.pos]) catch return TokenError.OutOfMemory;
                self.pos += 1;
                continue;
            }

            // Start a quoted section within the word
            if (c == '"' or c == '\'') {
                try self.parseQuotedString(buffer, c);
                continue;
            }

            buffer.append(c) catch return TokenError.OutOfMemory;
            self.pos += 1;
        }
    }

    /// Check if a character is whitespace
    fn isWhitespace(c: u8) bool {
        return c == ' ' or c == '\t' or c == '\n' or c == '\r';
    }
};

/// Parse a command line into command name and arguments
pub const ParsedCommand = struct {
    command: []const u8,
    args: [][]const u8,
    raw_args: [][]u8,
    allocator: Allocator,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.args);
    }
};

/// Parse a command line string into a ParsedCommand
pub fn parseCommandLine(allocator: Allocator, input: []const u8) !ParsedCommand {
    var tokenizer = Tokenizer.init(allocator);
    defer tokenizer.deinit();

    const tokens = tokenizer.tokenize(input) catch |err| {
        return switch (err) {
            TokenError.OutOfMemory => error.OutOfMemory,
            else => error.InvalidInput,
        };
    };

    if (tokens.len == 0) {
        return ParsedCommand{
            .command = "",
            .args = &[_][]const u8{},
            .raw_args = &[_][]u8{},
            .allocator = allocator,
        };
    }

    // Copy tokens to owned memory since tokenizer will be deinitialized
    const owned_args = try allocator.alloc([]const u8, tokens.len);
    for (tokens, 0..) |token, i| {
        owned_args[i] = try allocator.dupe(u8, token);
    }

    return ParsedCommand{
        .command = owned_args[0],
        .args = owned_args,
        .raw_args = @constCast(owned_args),
        .allocator = allocator,
    };
}

/// Free a ParsedCommand
pub fn freeCommand(cmd: *ParsedCommand) void {
    for (cmd.args) |arg| {
        cmd.allocator.free(@constCast(arg));
    }
    cmd.allocator.free(@constCast(cmd.args));
}

// Tests
test "basic tokenization" {
    const allocator = std.testing.allocator;

    var tokenizer = Tokenizer.init(allocator);
    defer tokenizer.deinit();

    const tokens = try tokenizer.tokenize("ls -la /home");
    try std.testing.expectEqual(@as(usize, 3), tokens.len);
    try std.testing.expectEqualStrings("ls", tokens[0]);
    try std.testing.expectEqualStrings("-la", tokens[1]);
    try std.testing.expectEqualStrings("/home", tokens[2]);
}

test "quoted string tokenization" {
    const allocator = std.testing.allocator;

    var tokenizer = Tokenizer.init(allocator);
    defer tokenizer.deinit();

    const tokens = try tokenizer.tokenize("echo \"hello world\"");
    try std.testing.expectEqual(@as(usize, 2), tokens.len);
    try std.testing.expectEqualStrings("echo", tokens[0]);
    try std.testing.expectEqualStrings("hello world", tokens[1]);
}

test "single quoted string" {
    const allocator = std.testing.allocator;

    var tokenizer = Tokenizer.init(allocator);
    defer tokenizer.deinit();

    const tokens = try tokenizer.tokenize("echo 'hello world'");
    try std.testing.expectEqual(@as(usize, 2), tokens.len);
    try std.testing.expectEqualStrings("echo", tokens[0]);
    try std.testing.expectEqualStrings("hello world", tokens[1]);
}

test "mixed quotes" {
    const allocator = std.testing.allocator;

    var tokenizer = Tokenizer.init(allocator);
    defer tokenizer.deinit();

    const tokens = try tokenizer.tokenize("echo \"hello\"'world'");
    try std.testing.expectEqual(@as(usize, 2), tokens.len);
    try std.testing.expectEqualStrings("echo", tokens[0]);
    try std.testing.expectEqualStrings("helloworld", tokens[1]);
}

test "escape sequences" {
    const allocator = std.testing.allocator;

    var tokenizer = Tokenizer.init(allocator);
    defer tokenizer.deinit();

    const tokens = try tokenizer.tokenize("echo hello\\ world");
    try std.testing.expectEqual(@as(usize, 2), tokens.len);
    try std.testing.expectEqualStrings("echo", tokens[0]);
    try std.testing.expectEqualStrings("hello world", tokens[1]);
}

test "empty input" {
    const allocator = std.testing.allocator;

    var tokenizer = Tokenizer.init(allocator);
    defer tokenizer.deinit();

    const tokens = try tokenizer.tokenize("");
    try std.testing.expectEqual(@as(usize, 0), tokens.len);
}

test "whitespace only" {
    const allocator = std.testing.allocator;

    var tokenizer = Tokenizer.init(allocator);
    defer tokenizer.deinit();

    const tokens = try tokenizer.tokenize("   \t   ");
    try std.testing.expectEqual(@as(usize, 0), tokens.len);
}

test "unterminated quote error" {
    const allocator = std.testing.allocator;

    var tokenizer = Tokenizer.init(allocator);
    defer tokenizer.deinit();

    const result = tokenizer.tokenize("echo \"hello");
    try std.testing.expectError(TokenError.UnterminatedQuote, result);
}
