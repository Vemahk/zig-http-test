const std = @import("std");
const zap = @import("zap");

const HttpMethod = @import("http.zig").HttpMethod;

const Allocator = std.mem.Allocator;
const Request = zap.SimpleRequest;

pub const RequestFn = *const fn (self: *const Endpoint, r: Request) void;
pub const Endpoint = struct {
    allocator: Allocator,
    path: []const u8,
    get: ?RequestFn = null,
    post: ?RequestFn = null,
    put: ?RequestFn = null,
    delete: ?RequestFn = null,
    patch: ?RequestFn = null,

    pub fn onRequest(self: *const Endpoint, r: Request) void {
        const methodStr = r.method orelse "";
        const method = HttpMethod.fromStr(methodStr);
        if (method) |m| {
            switch (m) {
                .Get => if (self.get) |f| f(self, r),
                .Post => if (self.post) |f| f(self, r),
                .Put => if (self.put) |f| f(self, r),
                .Delete => if (self.delete) |f| f(self, r),
                .Patch => if (self.patch) |f| f(self, r),
                //else => std.debug.print("unsupported method: {s}\n", .{methodStr}),
            }
        } else {
            std.debug.print("unknown method: {s}\n", .{methodStr});
        }
    }
};
