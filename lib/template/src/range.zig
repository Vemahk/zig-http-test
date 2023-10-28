pub fn Range(comptime T: type) type {
    return struct {
        const Self = @This();
        start: usize,
        end: usize,

        pub fn len(self: Self) usize {
            return self.end - self.start;
        }

        pub fn of(self: Self, slice: []const T) []const T {
            return slice[self.start..self.end];
        }

        pub fn before(self: Self, slice: []const T) []const T {
            return slice[0..self.start];
        }

        pub fn after(self: Self, slice: []const T) []const T {
            return slice[self.end..];
        }
    };
}
