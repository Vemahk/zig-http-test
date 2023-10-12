const std = @import("std");
const PathIter = @import("path-iter.zig");

const Allocator = std.mem.Allocator;

pub fn Trie(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        children: std.StringHashMap(Self),

        value: ?T = null,

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
                .children = std.StringHashMap(Self).init(allocator),
            };
        }

        pub fn add(self: *Self, path: []const u8, val: T) !void {
            var pathIter = PathIter{ .path = path };
            var node = self;
            while (try pathIter.next()) |segment| {
                var mapEntry = try node.children.getOrPut(segment);
                if (!mapEntry.found_existing) {
                    mapEntry.value_ptr.* = Self.init(self.allocator);
                }

                node = mapEntry.value_ptr;
            }

            if (node.*.value) |_| return error.DuplicateRecord;
            node.*.value = val;
        }

        pub fn get(self: *Self, path: []const u8) !?T {
            var pathIter = PathIter{ .path = path };
            var node = self;
            while (try pathIter.next()) |segment| {
                var nChild = node.children.getPtr(segment);
                if (nChild) |child| {
                    node = child;
                } else {
                    return null;
                }
            }

            return node.value;
        }

        pub fn deinit(self: *Self) void {
            var iter = self.children.valueIterator();
            while (iter.next()) |child| {
                child.deinit();
            }
            self.children.deinit();
        }
    };
}

test "then adding paths adds paths" {
    const testing = std.testing;
    var allocator = testing.allocator;

    var trie = Trie(u8).init(allocator);
    defer trie.deinit();
    try trie.add("/foo/baz", 7);

    const expect = testing.expect;
    try expect(try trie.get("/foo/baz") orelse unreachable == 7);
    try expect(try trie.get("/foo") == null);
    try expect(try trie.get("/bar") == null);
    try expect(try trie.get("/foo/bar") == null);
}

test "then duplicate key causes error" {
    const testing = std.testing;
    var allocator = testing.allocator;

    var trie = Trie(u8).init(allocator);
    defer trie.deinit();
    try trie.add("/foo/baz", 7);
    try testing.expectError(error.DuplicateRecord, trie.add("/foo/baz", 8));
}
