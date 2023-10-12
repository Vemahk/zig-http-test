const std = @import("std");
const Allocator = std.mem.Allocator;
const AtomicBool = std.atomic.Atomic(bool);

const zap = @import("zap");
const Listener = zap.SimpleHttpListener;
const ListenerSettings = zap.SimpleHttpListenerSettings;
const Err = zap.EndpointListenerError;
const Request = zap.SimpleRequest;
const RequestFn = zap.SimpleHttpRequestFn;

const Controllers = @import("controller.zig");
const Controller = Controllers.Controller;
const Endpoint = Controllers.Endpoint;

const Router = @import("path-trie.zig").Trie(Controller);

//Singleton? I hardly know 'er!
var has_init: AtomicBool = AtomicBool.init(false);
var allocator: Allocator = undefined;
var router: Router = undefined;
var not_found_handler: RequestFn = defaultNotFound;

pub fn init(a: std.mem.Allocator, not_found: ?RequestFn) !void {
    if (has_init.swap(true, .AcqRel))
        return error.SingletonReinit;

    allocator = a;
    router = Router.init(a);
    if (not_found) |alt_not_found|
        not_found_handler = alt_not_found;
}

pub fn deinit() void {
    router.deinit();
}

pub fn add(endpoint: *const Endpoint) !void {
    try router.add(endpoint.path, Controller{
        .allocator = allocator,
        .endpoint = endpoint,
    });
}

pub fn listen(l: ListenerSettings) !void {
    var ls = l;
    ls.on_request = route;
    var listener = Listener.init(ls);
    try listener.listen();
    std.debug.print("Listening on 0.0.0.0:{d}\n", .{listener.settings.port});
}

fn route(r: Request) void {
    if (r.path) |p| {
        if (router.get(p) catch null) |c|
            return c.onRequest(r);
    }

    return not_found_handler(r);
}

fn defaultNotFound(r: Request) void {
    r.setStatus(zap.StatusCode.not_found);
    r.markAsFinished(true);
}
