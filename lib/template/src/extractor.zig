const std = @import("std");
const Tokenizer = @import("tokenizer.zig");
const Tag = Tokenizer.Tag;

const FieldExtractor = struct {
    const Self = @This();
    const FieldTags = [_]Tag{ .period, .l_brace, .identifier, .r_brace };

    tokenizer: Tokenizer,

    pub fn init(html: []const u8) Self {
        return .{
            .tokenizer = .{
                .html = html,
            },
        };
    }

    pub fn next(self: *Self) ?StrRange {
        var tokens: [FieldTags.len]Token = undefined;
        var i: usize = 0;

        while (self.tokenizer.next()) |token| {
            if (token.tag == .eof)
                break;

            if (token.tag == FieldTags[i]) {
                tokens[i] = token;
                i += 1;
                if (i >= FieldTags.len) {
                    const marker_range = StrRange{
                        .start = tokens[0].range.start,
                        .end = token.range.end,
                    };

                    //empty identifier
                    if (std.mem.eql(u8, marker_range.of(self.html), ".{@\"\"}")) {
                        i = 0;
                        continue;
                    }

                    return marker_range;
                }
            } else if (token.tag == FieldTags[0]) {
                tokens[0] = token;
                i = 1;
            } else {
                i = 0;
            }
        }

        return null;
    }
};

test "extractor" {
    const expect = std.testing.expect;
    const expectStr = std.testing.expectEqualStrings;

    // 1 - happy path; one tag
    var html: [:0]const u8 = "<html>.{field_nm}</html>";
    var tokenizer = Tokenizer.init(html);

    var marker = tokenizer.next() orelse unreachable;
    try expectStr(".{field_nm}", marker.of(html));
    try expectStr("<html>", marker.before(html));
    try expectStr("</html>", marker.after(html));

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
    try expectStr(".{field_nm}", marker.marker_range.of(html));
    try expectStr("field_nm", marker.name_range.of(html));
    try expectStr("", marker.marker_range.before(html));
    try expectStr("", marker.marker_range.after(html));

    try expect(tokenizer.next() == null);

    // 6 - multiple tags
    html = "<html>.{field_nm}</html>.{field_nm}";
    tokenizer = Tokenizer.init(html);
    marker = tokenizer.next() orelse unreachable;
    try expectStr(".{field_nm}", marker.marker_range.of(html));
    try expectStr("field_nm", marker.name_range.of(html));
    try expectStr("</html>.{field_nm}", marker.marker_range.after(html));
    try expectStr("<html>", marker.marker_range.before(html));

    marker = tokenizer.next() orelse unreachable;
    try expectStr(".{field_nm}", marker.marker_range.of(html));
    try expectStr("field_nm", marker.name_range.of(html));
    try expectStr("", marker.marker_range.after(html));
    try expectStr("<html>.{field_nm}</html>", marker.marker_range.before(html));

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
    try expectStr(".{field_nm}", marker.marker_range.of(html));
    try expectStr("field_nm", marker.name_range.of(html));
    try expectStr("}</html>", marker.marker_range.after(html));
    try expectStr("<html>.{", marker.marker_range.before(html));
    try expect(tokenizer.next() == null);

    // 10 - string identifiers
    html = "<html>.{@\"420\"}</html>";
    tokenizer = Tokenizer.init(html);
    marker = tokenizer.next() orelse unreachable;
    try expectStr(".{@\"420\"}", marker.marker_range.of(html));
    try expectStr("420", marker.name_range.of(html));
    try expectStr("</html>", marker.marker_range.after(html));
    try expectStr("<html>", marker.marker_range.before(html));
    try expect(tokenizer.next() == null);

    // 11 - identifiers cannot be blank
    html = "<html>.{@\"\"}</html>";
    tokenizer = Tokenizer.init(html);
    try expect(tokenizer.next() == null);

    // 12 - some bastard token from hell.
    html = "<html>.{@\".{field_nm}\"}</html>";
    tokenizer = Tokenizer.init(html);
    marker = tokenizer.next() orelse unreachable;
    try expectStr(".{@\".{field_nm}\"}", marker.marker_range.of(html));
    try expectStr(".{field_nm}", marker.name_range.of(html));
    try expectStr("</html>", marker.marker_range.after(html));
    try expectStr("<html>", marker.marker_range.before(html));
    try expect(tokenizer.next() == null);

    html = "\".{field_nm}\"";
    tokenizer = Tokenizer.init(html);
    marker = tokenizer.next() orelse unreachable;
    try expectStr(".{field_nm}", marker.marker_range.of(html));
    try expectStr("field_nm", marker.name_range.of(html));
    try expectStr("\"", marker.marker_range.after(html));
    try expectStr("\"", marker.marker_range.before(html));
}

test {
    const T = struct {
        @"\"Hello, World!\"": u8,
        @" ": u8,
        @"fn": u8,
    };

    const info = @typeInfo(T).Struct.fields;
    try std.testing.expectEqualStrings("\"Hello, World!\"", info[0].name);
    try std.testing.expectEqualStrings(" ", info[1].name);
    try std.testing.expectEqualStrings("fn", info[2].name);
}
