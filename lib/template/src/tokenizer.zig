const std = @import("std");
const isKeyword = std.zig.Token.keywords.has;

const Range = @import("range.zig").Range;

pub const Token = struct {
    tag: Tag,
    range: Range(u8),
};

pub const Tag = enum(u8) {
    other,
    line_break,
    keyword,
    eof,

    period,
    l_brace,
    identifier,
    r_brace,
};

const State = enum(u8) {
    start,
    other,
    at_sign,
    string_literal,
    string_literal_escape,
    identifier,
    line_break,
    end,
};

const Self = @This();

tmpl: []const u8,
index: usize = 0,

pub fn next(self: *Self) Token {
    if (self.index >= self.tmpl.len)
        return .{ .tag = Tag.eof, .range = .{ .start = self.tmpl.len, .end = self.tmpl.len } };

    var state = State.start;
    var tag = Tag.other;
    const start = self.index;

    while (self.index < self.tmpl.len) : (self.index += 1) {
        const c = self.tmpl[self.index];
        switch (state) {
            .end => break,
            .start => {
                switch (c) {
                    '.' => {
                        tag = Tag.period;
                        state = State.end;
                    },
                    '{' => {
                        tag = Tag.l_brace;
                        state = State.end;
                    },
                    '}' => {
                        tag = Tag.r_brace;
                        state = State.end;
                    },
                    '@' => state = State.at_sign,
                    'a'...'z', 'A'...'Z', '_' => {
                        state = State.identifier;
                        tag = Tag.identifier;
                    },
                    '\r', '\n' => {
                        state = State.line_break;
                        tag = Tag.line_break;
                    },
                    else => state = State.other,
                }
            },
            .other => {
                switch (c) {
                    '.', '\r', '\n' => break,
                    else => {},
                }
            },
            .at_sign => {
                switch (c) {
                    '"' => {
                        tag = Tag.identifier;
                        state = State.string_literal;
                    },
                    '.', '\r', '\n' => break,
                    else => state = State.other,
                }
            },
            .identifier => {
                switch (c) {
                    'a'...'z', 'A'...'Z', '0'...'9', '_' => {},
                    else => {
                        if (isKeyword(self.tmpl[start..self.index])) {
                            tag = Tag.keyword;
                        }
                        state = State.end;
                        break;
                    },
                }
            },
            .string_literal => {
                switch (c) {
                    '"' => state = State.end,
                    '\\' => state = State.string_literal_escape,
                    '\r', '\n' => break,
                    else => {},
                }
            },
            .string_literal_escape => {
                switch (c) {
                    '\r', '\n' => break,
                    else => state = State.string_literal,
                }
            },
            .line_break => {
                switch (c) {
                    '\r', '\n' => {},
                    else => {
                        state = State.end;
                        break;
                    },
                }
            },
        }
    }

    if (state != State.end and tag != Tag.line_break)
        tag = Tag.other;

    return Token{
        .tag = tag,
        .range = .{
            .start = start,
            .end = self.index,
        },
    };
}

test "tokenizer" {
    const expectEq = std.testing.expectEqual;
    const expectStr = std.testing.expectEqualStrings;

    const Test = struct {
        tmpl: []const u8,
        expectedTags: []const Tag,
        expectedStrs: []const []const u8,

        pub fn assert(comptime T: @This()) !void {
            var tokenizer = Self{ .tmpl = T.tmpl };
            var i: usize = 0;

            while (true) : (i += 1) {
                const token = tokenizer.next();

                if (token.tag == .eof) {
                    try expectEq(T.expectedTags.len, i);
                    break;
                }
                try expectEq(T.expectedTags[i], token.tag);
                try expectStr(T.expectedStrs[i], token.range.of(T.tmpl));
            }
        }
    };

    try Test.assert(.{ // 1 - happy path; one tag
        .tmpl = "<html>.{field_nm}</html>",
        .expectedTags = &[_]Tag{ .other, .period, .l_brace, .identifier, .r_brace, .other },
        .expectedStrs = &[_][]const u8{ "<html>", ".", "{", "field_nm", "}", "</html>" },
    });

    try Test.assert(.{ // 2 - empty tag no identifier
        .tmpl = "<html>.{}</html>",
        .expectedTags = &[_]Tag{ .other, .period, .l_brace, .r_brace, .other },
        .expectedStrs = &[_][]const u8{ "<html>", ".", "{", "}", "</html>" },
    });

    try Test.assert(.{ // 3 - tag with reserved zig keyword
        .tmpl = "<html>.{fn}</html>",
        .expectedTags = &[_]Tag{ .other, .period, .l_brace, .keyword, .r_brace, .other },
        .expectedStrs = &[_][]const u8{ "<html>", ".", "{", "fn", "}", "</html>" },
    });

    try Test.assert(.{ // 4 - tag no html
        .tmpl = ".{field_nm}",
        .expectedTags = &[_]Tag{ .period, .l_brace, .identifier, .r_brace },
        .expectedStrs = &[_][]const u8{ ".", "{", "field_nm", "}" },
    });

    try Test.assert(.{ // 5 - tag inside quotations
        .tmpl = "<time datetime=\".{field_nm}\"></time>",
        .expectedTags = &[_]Tag{ .other, .period, .l_brace, .identifier, .r_brace, .other },
        .expectedStrs = &[_][]const u8{ "<time datetime=\"", ".", "{", "field_nm", "}", "\"></time>" },
    });

    try Test.assert(.{ // 6 - multiple tags
        .tmpl = "<html>.{field_nm}</html>.{field_nm}",
        .expectedTags = &[_]Tag{ .other, .period, .l_brace, .identifier, .r_brace, .other, .period, .l_brace, .identifier, .r_brace },
        .expectedStrs = &[_][]const u8{ "<html>", ".", "{", "field_nm", "}", "</html>", ".", "{", "field_nm", "}" },
    });

    try Test.assert(.{ // 7 - invalid tag
        .tmpl = "<html>.{{field_nm}}</html>",
        .expectedTags = &[_]Tag{ .other, .period, .l_brace, .l_brace, .identifier, .r_brace, .r_brace, .other },
        .expectedStrs = &[_][]const u8{ "<html>", ".", "{", "{", "field_nm", "}", "}", "</html>" },
    });

    try Test.assert(.{ // 8 - incomplete tag
        .tmpl = "<html>.{field_nm</html>",
        .expectedTags = &[_]Tag{ .other, .period, .l_brace, .identifier, .other },
        .expectedStrs = &[_][]const u8{ "<html>", ".", "{", "field_nm", "</html>" },
    });

    try Test.assert(.{ // 9 - string identifiers
        .tmpl = "<html>.{@\"420\"}</html>",
        .expectedTags = &[_]Tag{ .other, .period, .l_brace, .identifier, .r_brace, .other },
        .expectedStrs = &[_][]const u8{ "<html>", ".", "{", "@\"420\"", "}", "</html>" },
    });

    try Test.assert(.{ // 10 - blank identifier still gets tokenized as identifier
        .tmpl = "<html>.{@\"\"}</html>",
        .expectedTags = &[_]Tag{ .other, .period, .l_brace, .identifier, .r_brace, .other },
        .expectedStrs = &[_][]const u8{ "<html>", ".", "{", "@\"\"", "}", "</html>" },
    });

    try Test.assert(.{ // 11 - some bastard token from hell.
        .tmpl = "<html>.{@\".{field_nm}\"}</html>",
        .expectedTags = &[_]Tag{ .other, .period, .l_brace, .identifier, .r_brace, .other },
        .expectedStrs = &[_][]const u8{ "<html>", ".", "{", "@\".{field_nm}\"", "}", "</html>" },
    });

    try Test.assert(.{ // 12 - eol terminates identifier
        .tmpl =
        \\.{field
        \\}
        ,
        .expectedTags = &[_]Tag{ .period, .l_brace, .identifier, .line_break, .r_brace },
        .expectedStrs = &[_][]const u8{ ".", "{", "field", "\n", "}" },
    });

    try Test.assert(.{ // 13 - eol invalidates literal identifier
        .tmpl =
        \\.{@"field
        \\
        ,
        .expectedTags = &[_]Tag{ .period, .l_brace, .other, .line_break },
        .expectedStrs = &[_][]const u8{ ".", "{", "@\"field", "\n" },
    });
}

test {
    const T = struct {
        @"\"Hello, World!\"": u8,
        @" ": u8,
        @"fn": u8,
        @"\"": u8,
    };

    const info = @typeInfo(T).Struct.fields;
    try std.testing.expectEqualStrings("\"Hello, World!\"", info[0].name);
    try std.testing.expectEqualStrings(" ", info[1].name);
    try std.testing.expectEqualStrings("fn", info[2].name);
    try std.testing.expectEqualStrings("\"", info[3].name);
}
