const std = @import("std");

const TemplateNS = @import("../template.zig");
const Template = TemplateNS.Template;

pub const TemplaterOptions = struct {
    embed_html: bool = false,
};

pub fn init(comptime T: type, comptime file_path: []const u8) type {
    return initOptions(T, file_path, .{});
}

fn initOptions(comptime T: type, comptime file_path: []const u8, comptime opts: TemplaterOptions) type {
    return struct {
        var tmpl: ?Template(T) = null;
        pub fn get(allocator: std.mem.Allocator) !*const Template(T) {
            if (tmpl == null) {
                //TODO: these are never deinited... do we care?
                //TODO: make creation thread-safe.

                tmpl = (if (opts.embed_html)
                    Template(T).init(allocator, @embedFile(file_path))
                else
                    Template(T).initFromFile(allocator, file_path)) catch |err| {
                    std.log.err("Failed to generate Template from {s}\n", .{file_path});
                    return err;
                };
            }

            return &tmpl.?;
        }
    };
}
