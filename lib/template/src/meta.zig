const std = @import("std");

pub fn fieldNames(comptime T: type) [@typeInfo(T).Struct.fields.len][]const u8 {
    return comptime blk: {
        const fields = @typeInfo(T).Struct.fields;
        var field_names: [fields.len][]const u8 = undefined;
        for (fields, 0..) |f, i| {
            field_names[i] = f.name;
        }
        break :blk field_names;
    };
}

test {
    const MyStruct = struct {
        field_one: []const u8,
        field_two: comptime_int,
    };

    const field_names = fieldNames(MyStruct);

    const expect = std.testing.expect;
    try expect(field_names.len == 2);

    const expectStr = std.testing.expectEqualStrings;
    try expectStr("field_one", field_names[0]);
    try expectStr("field_two", field_names[1]);
}
