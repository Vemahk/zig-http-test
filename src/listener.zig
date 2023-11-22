const std = @import("std");
const Allocator = std.mem.Allocator;
const AtomicBool = std.atomic.Atomic(bool);

const zap = @import("zap");
const Listener = zap.SimpleHttpListener;
const ListenerSettings = zap.SimpleHttpListenerSettings;
const Err = zap.EndpointListenerError;
const Request = zap.SimpleRequest;
const RequestFn = zap.SimpleHttpRequestFn;

const Endpoint = @import("endpoint.zig");

const Router = @import("path.zig").Paths(Endpoint);

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

pub fn add(comptime endpoint: Endpoint) !void {
    try router.add(endpoint.path, endpoint);
}

var listener: Listener = undefined;
pub fn listen(l: ListenerSettings) !void {
    var ls = l;
    ls.on_request = route;
    listener = Listener.init(ls);
    try listener.listen();
    std.debug.print("Listening on 0.0.0.0:{d}\n", .{listener.settings.port});
}

fn route(r: Request) void {
    if (r.path) |p| {
        if (router.find(p) catch null) |c| {
            const ctx = Endpoint.Context{
                .request = r,
                .allocator = allocator,
                .id = c[1],
            };
            return c[0].onRequest(ctx);
        }
    }

    return not_found_handler(r);
}

fn defaultNotFound(r: Request) void {
    r.setStatus(zap.StatusCode.not_found);
    r.markAsFinished(true);
}
