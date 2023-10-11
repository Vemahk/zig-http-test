const std = @import("std");
const zap = @import("zap");
const utils = @import("utils");

const Router = std.StringHashMap(zap.SimpleHttpRequestFn);
var routes: Router = undefined;
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var allocator = arena.allocator();

    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");

    std.debug.print("cwd: {s}\n", .{cwd});
}
