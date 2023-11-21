const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.templates);

pub const Templater = struct {
    Data: type,
    get: *const fn (allocator: Allocator) Template,
};

pub const Layout = init(struct { title: []const u8, content: []const u8 }, .{ .file_path = "layout.html" });
pub const Time = init(struct { timestamp: i64 }, .{ .file_path = "time.html" });

const mustache = @import("mustache");
const Template = mustache.Template;
const errored_template = mustache.parseComptime("Template Error", .{}, .{});

const is_debug = @import("builtin").mode == .Debug;

const Options = struct {
    file_path: []const u8,
    embed: bool = !is_debug,
};

const root_path = "resources/private/templates/";

fn init(comptime T: type, comptime opts: Options) Templater {
    return Templater{
        .Data = T,
        .get = if (opts.embed) struct {
            const file_path = "../" ++ root_path ++ opts.file_path; // TODO this doesn't actually work :(
            const template = mustache.parseComptime(@embedFile(file_path), .{}, .{});
            pub fn get(allocator: Allocator) Template {
                _ = allocator;
                return template;
            }
        }.get else struct {
            const file_path = root_path ++ opts.file_path;
            var tmpl: ?Template = null;
            pub fn get(allocator: Allocator) Template {
                if (should_rebuild())
                    rebuild(allocator);

                return tmpl.?;
            }

            var lock: std.Thread.Mutex = .{};
            var load_time: i128 = 0;
            fn rebuild(allocator: Allocator) void {
                lock.lock();
                defer lock.unlock();
                if (tmpl) |t| t.deinit(allocator);
                tmpl = create(allocator) catch |err| blk: {
                    log.err("Failed to parse template {s} ({s})\n", .{ file_path, @errorName(err) });
                    break :blk errored_template;
                };

                load_time = std.time.nanoTimestamp();
            }

            fn create(allocator: Allocator) !Template {
                const absolute_path = try std.fs.cwd().realpathAlloc(allocator, file_path);
                const template = try mustache.parseFile(allocator, absolute_path, .{}, .{});
                switch (template) {
                    .success => |t| {
                        log.debug("(re)Built template of {s}\n", .{file_path});
                        return t;
                    },
                    .parse_error => |e| {
                        log.warn("Failed to build template of {s}: ({d},{d})\n", .{ file_path, e.lin, e.col });
                        return e.parse_error;
                    },
                }
            }

            fn should_rebuild() bool {
                if (tmpl == null)
                    return true;

                if (is_debug) {
                    const stat = std.fs.cwd().statFile(file_path) catch return false;
                    return stat.mtime > load_time;
                }

                return false;
            }
        }.get,
    };
}
