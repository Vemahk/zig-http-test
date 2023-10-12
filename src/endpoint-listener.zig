const std = @import("std");
const zap = @import("zap");

const Endpoint = @import("endpoint.zig").Endpoint;
const Listener = zap.SimpleHttpListener;
const ListenerSettings = zap.SimpleHttpListenerSettings;
const Err = zap.EndpointListenerError;
const Request = zap.SimpleRequest;
const RequestFn = zap.SimpleHttpRequestFn;
const EndpointTrie = @import("path-trie.zig").Trie(*const Endpoint);
const Allocator = std.mem.Allocator;

//Singleton? I hardly know 'er!
const Self = @This();

var allocator: Allocator = undefined;
var listener: Listener = undefined;
var endpoints: EndpointTrie = undefined;
var not_found_handler: ?RequestFn = null;

pub fn init(a: std.mem.Allocator, l: ListenerSettings) void {
    allocator = a;
    not_found_handler = l.on_request;
    endpoints = EndpointTrie.init(a);

    var ls = l; // cpy
    ls.on_request = onRequest;
    listener = Listener.init(ls);
}

pub fn deinit() void {
    endpoints.deinit();
}

pub fn add(e: anytype) !void {
    e.init(allocator);
    const endpoint: *const Endpoint = e.getEndpointPtr();
    const path = endpoint.path;
    try endpoints.add(path, endpoint);
}

pub fn listen() !void {
    try listener.listen();
    std.debug.print("Listening on 0.0.0.0:{d}\n", .{listener.settings.port});
}

fn onRequest(r: Request) void {
    if (r.path) |p| {
        if (endpoints.get(p) catch null) |e| {
            e.onRequest(r);
            return;
        }
    }
    if (not_found_handler) |foo| {
        foo(r);
    }
}
