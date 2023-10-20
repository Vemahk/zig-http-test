pub const Layout = init(struct { title: []const u8, content: []const u8 }, "private/templates/layout.html", .{});
pub const Time = init(struct { timestamp: i64 }, "private/templates/time.html", .{});

const std = @import("std");
const Template = @import("template.zig").Template;
const TemplaterOptions = struct {
    embed_html: bool = false,
};

fn init(comptime T: type, comptime file_path: []const u8, comptime opts: TemplaterOptions) type {
    return struct {
        pub const Data = T;

        var lock: std.Thread.Mutex = .{};

        var tmpl: ?Template(T) = null;
        pub fn get(allocator: std.mem.Allocator) !*const Template(T) {
            if (tmpl == null)
                try rebuild(allocator);

            return &tmpl.?;
        }

        pub fn rebuild(allocator: std.mem.Allocator) !void {
            lock.lock();
            defer lock.unlock();
            if (tmpl) |t| t.deinit();
            tmpl = try create(allocator);
        }

        fn create(allocator: std.mem.Allocator) !Template(T) {
            return (if (opts.embed_html)
                Template(T).init(allocator, @embedFile(file_path))
            else
                Template(T).initFromFile(allocator, file_path)) catch |err| {
                std.log.err("Failed to generate Template from {s}\n", .{file_path});
                return err;
            };
        }
    };
}
