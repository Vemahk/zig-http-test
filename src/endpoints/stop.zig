const C = @import("_common.zig");
const zap = @import("zap");

pub const path = "/stop";

pub fn get(ctx: C.HttpContext) !void {
    if (@import("builtin").mode != .Debug) {
        return;
    }

    zap.stop();
    ctx.exit(zap.StatusCode.ok);
}
