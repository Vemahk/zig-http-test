const std = @import("std");
const zap = @import("zap");

const Allocator = std.mem.Allocator;
const Endpoint = @import("../endpoint.zig").Endpoint;
const Request = zap.SimpleRequest;

const layout_format = @embedFile("../content/layout.html");

const Self = @This();

var endpoint: Endpoint = undefined;

pub fn init(a: Allocator) void {
    endpoint = .{
        .allocator = a,
        .path = "/",
        .get = get,
    };
}

pub fn getEndpointPtr() *const Endpoint {
    return &Self.endpoint;
}

fn get(e: *const Endpoint, r: Request) void {
    var buffer = std.ArrayList(u8).init(e.allocator);
    defer buffer.deinit();
    var writer = buffer.writer();
    std.fmt.format(writer, layout_format, .{ "Hello, World!", "Not really any content..." }) catch return;
    r.sendBody(buffer.items) catch return;
}
