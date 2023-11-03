pub const Layout = init(struct { title: []const u8, content: []const u8 }, "private/templates/layout.html", .{});
pub const Time = init(struct { timestamp: i64 }, "private/templates/time.html", .{});

const std = @import("std");
const log = std.log.scoped(.templates);

const builtin = @import("builtin");
const TemplateNS = @import("template");
const Template = TemplateNS.Template;
const TemplaterOptions = struct {
    embed_html: bool = false,
};

fn init(comptime T: type, comptime file_path: []const u8, comptime opts: TemplaterOptions) type {
    return struct {
        pub const Data = T;

        var tmpl: ?Template(T) = null;
        var load_time: i128 = 0;
        pub fn get(allocator: std.mem.Allocator) !*const Template(T) {
            if (should_rebuild())
                try rebuild(allocator);

            return &tmpl.?;
        }

        var lock: std.Thread.Mutex = .{};
        pub fn rebuild(allocator: std.mem.Allocator) !void {
            const timestamp = std.time.microTimestamp;
            const start = timestamp();
            lock.lock();
            defer lock.unlock();
            if (tmpl) |t| t.deinit();
            tmpl = try create(allocator);
            load_time = std.time.nanoTimestamp();
            log.debug("(re)Built template of {s} ({d}us)", .{ file_path, timestamp() - start });
        }

        fn create(allocator: std.mem.Allocator) !Template(T) {
            return (if (opts.embed_html)
                Template(T).init(allocator, @embedFile(file_path))
            else
                Template(T).initFromFile(allocator, file_path)) catch |err| {
                log.err("Failed to generate Template from {s}\n", .{file_path});
                return err;
            };
        }

        fn should_rebuild() bool {
            if (tmpl == null) {
                return true;
            }

            if (builtin.mode == .Debug) {
                const stat = std.fs.cwd().statFile(file_path) catch return false;
                return stat.mtime > load_time;
            }

            return false;
        }
    };
}
