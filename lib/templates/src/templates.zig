const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.templates);

pub const Templater = struct {
    Data: type,
    get: *const fn (allocator: Allocator) Template,
};

pub const Layout = init(struct { title: []const u8, content: []const u8 }, .{ .file_path = "private/templates/layout.html" });
pub const Time = init(struct { timestamp: i64 }, .{ .file_path = "private/templates/time.html" });

const mustache = @import("mustache");
const Template = mustache.Template;
const errored_template = mustache.parseComptime("Template Error", .{}, .{});

const is_debug = @import("builtin").mode == .Debug;

const Options = struct {
    file_path: []const u8,
    embed: bool = !is_debug,
};

fn init(comptime T: type, comptime opts: Options) Templater {
    const file_path = opts.file_path;
    return Templater{
        .Data = T,
        .get = if (opts.embed) struct {
            const template = mustache.parseComptime(embedResource(file_path), .{}, .{});
            pub fn get(allocator: Allocator) Template {
                _ = allocator;
                return template;
            }
        }.get else struct {
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
                const template_text = try std.fs.cwd().readFileAlloc(allocator, file_path, 1 << 20);
                const template = try mustache.parseText(allocator, template_text, .{}, .{});
                log.debug("(re)Built template of {s}\n", .{file_path});
                return template;
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

fn embedResource(comptime file_path: []const u8) []const u8 {
    return @embedFile(file_path);
}
