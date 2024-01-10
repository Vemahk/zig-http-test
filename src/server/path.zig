// A resource identifier may be any string.
// A resource identifier is matched by the below string:
const wildcard = "*";

const std = @import("std");
const Allocator = std.mem.Allocator;

const Iter = @import("path-iter.zig");

pub const PathsError = error{
    MultipleWildcards,
    DuplicatePath,
    AmbiguousPath,
};

pub const ResourceId = struct {
    const Self = @This();
    str: ?[]const u8 = null,
};

pub fn Paths(comptime T: type) type {
    return struct {
        const Self = @This();
        const KV = struct { path: []const u8, value: T };
        pub const Result = struct { T, ResourceId };

        paths: std.ArrayList(KV),

        pub fn init(a: Allocator) Self {
            return .{
                .paths = std.ArrayList(KV).init(a),
            };
        }

        pub fn add(self: *Self, path_in: []const u8, value: T) !void {
            const a = self.paths.allocator;
            const path = try a.dupe(u8, path_in);
            errdefer a.free(path);

            try validatePath(path);

            for (self.paths.items) |kv| {
                if (try matches(path, kv.path)) |_|
                    return PathsError.AmbiguousPath;
            }

            try self.paths.append(.{ .path = path, .value = value });
        }

        pub fn find(self: Self, path: []const u8) !?Result {
            for (self.paths.items) |kv| {
                if (try matches(path, kv.path)) |resource_id| {
                    return .{ kv.value, resource_id };
                }
            }

            return null;
        }

        pub fn deinit(self: Self) void {
            const paths = self.paths;

            for (paths.items) |kv| {
                paths.allocator.free(kv.path);
            }

            paths.deinit();
        }
    };
}

test "then path resolves" {
    const a = std.testing.allocator;
    var paths = Paths(u8).init(a);
    defer paths.deinit();

    try paths.add("/foo", 0);
    try paths.add("/foo/bar", 1);
    try paths.add("/foo/bar/baz", 2);
    try paths.add("/foo/bar/*", 3);
    try paths.add("/foo/bar/*/baz", 4);

    const eqSlice = std.testing.expectEqualSlices;
    const eq = std.testing.expect;

    var r: Paths(u8).Result = undefined;

    r = try paths.find("/foo") orelse unreachable;
    try eq(r[0] == 0);

    r = try paths.find("/foo/bar") orelse unreachable;
    try eq(r[0] == 1);

    r = try paths.find("/foo/bar/baz") orelse unreachable;
    try eq(r[0] == 2);
    try eq(r[1].str == null);

    r = try paths.find("/foo/bar/123") orelse unreachable;
    try eq(r[0] == 3);
    try eqSlice(u8, "123", r[1].str.?);

    r = try paths.find("/foo/bar/124/baz") orelse unreachable;
    try eq(r[0] == 4);
    try eqSlice(u8, "124", r[1].str.?);
}

fn validatePath(path: []const u8) !void {
    var iter = Iter.init(path);
    var has_wildcard = false;
    while (try iter.next()) |i| {
        if (std.mem.eql(u8, i, wildcard)) {
            if (has_wildcard) {
                return PathsError.MultipleWildcards;
            }

            has_wildcard = true;
        }
    }
}

fn matches(input_path: []const u8, target_path: []const u8) !?ResourceId {
    var iter = Iter.init(input_path);
    var target_iter = Iter.init(target_path);
    var resource_id = ResourceId{};

    while (try iter.next()) |i| {
        if (try target_iter.next()) |t| {
            if (std.mem.eql(u8, t, wildcard)) {
                if (resource_id.str != null)
                    unreachable;

                resource_id.str = i;
            } else if (!std.mem.eql(u8, i, t)) {
                return null;
            }
        } else return null;
    }

    if (try target_iter.next()) |_| {
        return null;
    }

    return resource_id;
}
