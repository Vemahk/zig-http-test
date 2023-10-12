pub const PathErr = error{
    BadPath,
    EmptyPath,
};

const Self = @This();

path: []const u8,
i: usize = 0,

pub fn next(self: *Self) PathErr!?[]const u8 {
    const start = self.i;
    if (start >= self.path.len)
        return null;

    if (self.path[start] != '/')
        return PathErr.BadPath;

    var end = start + 1;
    while (end < self.path.len and self.path[end] != '/') {
        end += 1;
    }

    if (end == start + 1) {
        if (end == self.path.len) return null;
        return PathErr.EmptyPath;
    }
    self.i = end;
    return self.path[start + 1 .. end];
}

test "valid path parses" {
    const path = "/foo/bar/baz";
    var iter = Self{ .path = path };

    const testing = @import("std").testing;
    const expectEq = testing.expectEqualStrings;
    try expectEq("foo", try iter.next() orelse unreachable);
    try expectEq("bar", try iter.next() orelse unreachable);
    try expectEq("baz", try iter.next() orelse unreachable);

    const expect = testing.expect;
    try expect(try iter.next() == null);
}

test "then trailing slash is ignored" {
    const path = "/";
    var iter = Self{ .path = path };

    const testing = @import("std").testing;
    const expectEq = testing.expectEqualStrings;
    const expect = testing.expect;

    try expect(try iter.next() == null);

    const path2 = "/foo/";
    iter = Self{ .path = path2 };
    try expectEq("foo", try iter.next() orelse unreachable);
    try expect(try iter.next() == null);
}

test "then double slash causes error" {
    const path = "//";
    var iter = Self{ .path = path };

    const testing = @import("std").testing;
    const expect = testing.expect;
    try expect(iter.next() == PathErr.EmptyPath);
}

test "then non-path errors" {
    const path = "foo";
    var iter = Self{ .path = path };

    const testing = @import("std").testing;
    const expect = testing.expect;
    try expect(iter.next() == PathErr.BadPath);
}
