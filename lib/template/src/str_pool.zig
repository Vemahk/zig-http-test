const std = @import("std");
const Self = @This();

set: std.StringHashMap(u32),

pub fn init(a: std.mem.Allocator) Self {
    return .{
        .set = std.StringHashMap(u32).init(a),
    };
}

pub fn deinit(self: *Self) void {
    const a = self.set.allocator;
    var iter = self.set.keyIterator();
    while (iter.next()) |key_ptr| {
        a.free(key_ptr.*);
    }
    self.set.deinit();
}

/// Takes ownership of the given string.
/// The string must have been allocated by the same allocator that created this string pool.
/// Returns a reference to the interned string.
/// If this string pool already contained a reference for the given string, the given string will be deallocated.
/// If this string pool errors while attempting to intern the given string, the given string will be deallocated.
pub fn intern(self: *Self, str: []const u8) std.mem.Allocator.Error![]const u8 {
    const a = self.set.allocator;
    errdefer a.free(str);

    const count = self.set.count();
    const entry = try self.set.getOrPut(str);
    if (entry.found_existing) {
        a.free(str);
    } else {
        entry.value_ptr.* = count;
    }

    return entry.key_ptr.*;
}

pub fn toOwnedSlice(self: *Self) std.mem.Allocator.Error![]const []const u8 {
    const a = self.set.allocator;
    const count = self.set.count();
    var slice = try a.alloc([]const u8, count);
    var iter = self.set.iterator();
    while (iter.next()) |entry| {
        slice[entry.value_ptr.*] = entry.key_ptr.*;
    }

    self.set.clearAndFree();
    return slice;
}

test "string interning" {
    const a = std.testing.allocator;
    const expectStr = std.testing.expectEqualStrings;
    const expectEq = std.testing.expectEqual;
    const Test = struct {
        pub fn assert(in: []const []const u8, expected: []const []const u8) !void {
            var pool = Self.init(a);
            defer pool.deinit();

            var set = std.AutoHashMap([*]const u8, void).init(a);
            defer set.deinit();

            for (in) |str| {
                const interned = try pool.intern(try asOwned(str));
                try set.put(interned.ptr, {});
            }

            try expectEq(@as(usize, set.count()), expected.len);

            const actual = try pool.toOwnedSlice();
            defer {
                for (actual) |s| a.free(s);
                a.free(actual);
            }

            for (expected, actual) |str_expected, str_actual| {
                try expectStr(str_expected, str_actual);
            }
        }

        fn asOwned(str: []const u8) ![]const u8 {
            const owned = try a.alloc(u8, str.len);
            std.mem.copy(u8, owned, str);
            return owned;
        }
    };

    try Test.assert(&[_][]const u8{}, &[_][]const u8{});
    try Test.assert(&[_][]const u8{"a"}, &[_][]const u8{"a"});
    try Test.assert(&[_][]const u8{ "a", "a" }, &[_][]const u8{"a"});
    try Test.assert(&[_][]const u8{ "a", "b" }, &[_][]const u8{ "a", "b" });
    try Test.assert(&[_][]const u8{ "a", "b", "a" }, &[_][]const u8{ "a", "b" });
}
