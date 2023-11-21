pub const Index = declare(@import("endpoints/index.zig"));
pub const Time = declare(@import("endpoints/time.zig"));

const Endpoint = @import("endpoint.zig").Endpoint;

fn declare(comptime T: type) Endpoint {
    return Endpoint{
        .path = T.path,
        .get = if (@hasDecl(T, "get")) T.get else null,
        .post = if (@hasDecl(T, "post")) T.post else null,
        .put = if (@hasDecl(T, "put")) T.put else null,
        .delete = if (@hasDecl(T, "delete")) T.delete else null,
        .patch = if (@hasDecl(T, "patch")) T.patch else null,
    };
}
