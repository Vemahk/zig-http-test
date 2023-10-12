const std = @import("std");

const STR_GET = "GET";
const STR_POST = "POST";
const STR_PUT = "PUT";
const STR_DELETE = "DELETE";
const STR_PATCH = "PATCH";

pub const HttpMethod = enum(u8) {
    Get = 1,
    Post = 2,
    Put = 3,
    Delete = 4,
    Patch = 5,

    pub fn fromStr(nStr: ?[]const u8) ?HttpMethod {
        if (nStr == null) return null;

        const str = nStr.?;
        if (std.mem.eql(u8, str, STR_GET)) return .Get;
        if (std.mem.eql(u8, str, STR_POST)) return .Post;
        if (std.mem.eql(u8, str, STR_PUT)) return .Put;
        if (std.mem.eql(u8, str, STR_DELETE)) return .Delete;
        if (std.mem.eql(u8, str, STR_PATCH)) return .Patch;
        return null;
    }

    pub fn toStr(self: @This()) []const u8 {
        switch (self) {
            .Get => return STR_GET,
            .Post => return STR_POST,
            .Put => return STR_PUT,
            .Delete => return STR_DELETE,
            .Patch => return STR_PATCH,
        }
    }
};
