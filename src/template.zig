const std = @import("std");
const Allocator = std.mem.Allocator;

const meta = @import("meta.zig");

pub fn renderField(data: anytype, writer: anytype) !void {
    const T = @Type(data);
    const info: std.builtin.Type = @typeInfo(T);
    _ = info;
    _ = writer;
}

pub fn Template(comptime T: type) type {
    const Field = struct {};
    _ = Field;

    return struct {
        const Self = @This();

        allocator: Allocator,
        html: []const u8,
        markers: []const FieldMarker,

        const field_names = meta.fieldNames(T);

        pub fn init(a: Allocator, html_template: [:0]const u8) !Self {
            const logger = std.log.scoped(.template_init);
            var marker_list = std.ArrayList(FieldMarker).init(a);
            defer marker_list.deinit();

            var fields_used = [_]bool{false} ** field_names.len;

            var tokenizer = Tokenizer.init(html_template);
            while (tokenizer.next()) |marker| {
                const index: ?usize = blk: {
                    for (field_names, 0..) |field, i| {
                        if (std.mem.eql(u8, field, marker.name))
                            break :blk i;
                    }

                    break :blk null;
                };

                if (index) |i| {
                    fields_used[i] = true;
                    try marker_list.append(marker);
                } else {
                    logger.warn("Detected unknown field in template ({s}): '{s}'", .{ @typeName(T), marker.name });
                }
            }

            for (fields_used, 0..) |b, i| {
                if (!b) {
                    logger.warn("Field '{s}' not used in template for {s}", .{ field_names[i], @typeName(T) });
                }
            }

            return Self{
                .allocator = a,
                .html = html_template,
                .markers = try marker_list.toOwnedSlice(),
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.markers);
        }

        pub fn render(data: T, writer: anytype) !void {
            _ = writer;
            _ = data;
            const info = @typeInfo(T);
            const field = info.Struct.fields;

            for (field) |f| {
                _ = f;
            }
        }
    };
}

test "building template works." {
    const Data = struct {
        field_nm: []const u8,
        second_fld: usize,
    };
    const html = "<html>.{field_nm}.{missing_fld}</html>";
    const TestTemplate = Template(Data);
    var tmp = try TestTemplate.init(std.testing.allocator, html);
    defer tmp.deinit();
}

const ZTokenizer = std.zig.Tokenizer;
const ZToken = std.zig.Token;
const FieldMarkerTags = [_]ZToken.Tag{ .period, .l_brace, .identifier, .r_brace };

const FieldMarker = struct {
    const Self = @This();

    name: []const u8,
    start: usize,
    len: usize,
};

const Tokenizer = struct {
    const Self = @This();

    html: [:0]const u8,
    index: usize = 0,

    pub fn init(html: [:0]const u8) Self {
        return Self{
            .html = html,
        };
    }

    pub fn next(self: *Self) ?FieldMarker {
        while (self.index < self.html.len) {
            const start = self.index;
            var zt = ZTokenizer.init(self.html[start..]);

            var ztokens: [FieldMarkerTags.len]ZToken = undefined;
            var i: usize = 0;

            while (i < FieldMarkerTags.len) {
                const ztoken = zt.next();
                if (ztoken.tag == .eof) {
                    self.index = self.html.len;
                    break;
                }

                if (ztoken.tag == FieldMarkerTags[i]) {
                    ztokens[i] = ztoken;
                    i += 1;
                    if (i >= FieldMarkerTags.len) {
                        const marker_start = start + ztokens[0].loc.start;
                        const marker_end = start + ztoken.loc.end;
                        const name_ident = ztokens[2];
                        const name_start = start + name_ident.loc.start;
                        const name_end = start + name_ident.loc.end;
                        self.index = marker_end;

                        return .{
                            .name = self.html[name_start..name_end],
                            .start = marker_start,
                            .len = marker_end - marker_start,
                        };
                    }
                } else {
                    if (i > 0 and ztoken.tag == FieldMarkerTags[0]) {
                        self.index = start + ztoken.loc.start;
                        ztokens[0] = ztoken;
                        i = 1;
                        continue;
                    } else {
                        self.index = start + ztoken.loc.end;
                        break;
                    }
                }
            }
        }

        return null;
    }
};

test "tokenzier" {
    const expect = std.testing.expect;
    const expectStr = std.testing.expectEqualStrings;

    // 1 - happy path; one tag
    var html: [:0]const u8 = "<html>.{field_nm}</html>";
    var tokenizer = Tokenizer.init(html);

    var marker = tokenizer.next() orelse unreachable;
    try expectStr(".{field_nm}", html[marker.start .. marker.start + marker.len]);
    try expectStr("field_nm", marker.name);
    try expectStr("</html>", html[marker.start + marker.len ..]);
    try expectStr("<html>", html[0..marker.start]);

    try expect(tokenizer.next() == null);

    // 2 - empty tag no worky
    html = "<html>.{}</html>";
    tokenizer = Tokenizer.init(html);
    try expect(tokenizer.next() == null);

    // 3 - tag with reserved zig keyword
    html = "<html>.{fn}</html>";
    tokenizer = Tokenizer.init(html);
    try expect(tokenizer.next() == null);

    // 4 - tag no html
    html = ".{field_nm}";
    tokenizer = Tokenizer.init(html);
    marker = tokenizer.next() orelse unreachable;
    try expectStr(".{field_nm}", html[marker.start .. marker.start + marker.len]);
    try expectStr("field_nm", marker.name);
    try expectStr("", html[marker.start + marker.len ..]);
    try expectStr("", html[0..marker.start]);

    try expect(tokenizer.next() == null);

    // 6 - multiple tags
    html = "<html>.{field_nm}</html>.{field_nm}";
    tokenizer = Tokenizer.init(html);
    marker = tokenizer.next() orelse unreachable;
    try expectStr(".{field_nm}", html[marker.start .. marker.start + marker.len]);
    try expectStr("field_nm", marker.name);
    try expectStr("</html>.{field_nm}", html[marker.start + marker.len ..]);
    try expectStr("<html>", html[0..marker.start]);

    marker = tokenizer.next() orelse unreachable;
    try expectStr(".{field_nm}", html[marker.start .. marker.start + marker.len]);
    try expectStr("field_nm", marker.name);
    try expectStr("", html[marker.start + marker.len ..]);
    try expectStr("<html>.{field_nm}</html>", html[0..marker.start]);

    try expect(tokenizer.next() == null);

    // 7 - invalid tag
    html = "<html>.{{field_nm}}</html>";
    tokenizer = Tokenizer.init(html);
    try expect(tokenizer.next() == null);

    // 8 - incomplete tag
    html = "<html>.{field_nm</html>";
    tokenizer = Tokenizer.init(html);
    try expect(tokenizer.next() == null);

    // 9 - funky nested tag
    html = "<html>.{.{field_nm}}</html>";
    tokenizer = Tokenizer.init(html);
    marker = tokenizer.next() orelse unreachable;
    try expectStr(".{field_nm}", html[marker.start .. marker.start + marker.len]);
    try expectStr("field_nm", marker.name);
    try expectStr("}</html>", html[marker.start + marker.len ..]);
    try expectStr("<html>.{", html[0..marker.start]);
    try expect(tokenizer.next() == null);
}
