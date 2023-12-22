const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const main_path = std.Build.LazyPath{ .path = "main" };

    const root_source_file = std.Build.LazyPath{ .path = main_path.path ++ "/src/main.zig" };
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "http-test",
        .root_source_file = root_source_file,
        .target = target,
        .optimize = optimize,
        .main_pkg_path = main_path,
    });
    b.installArtifact(exe);

    // Add dependencies
    const mustache = b.dependency("mustache", .{
        .target = target,
        .optimize = optimize,
    });
    exe.addModule("mustache", mustache.module("mustache"));

    const zap = b.dependency("zap", .{
        .target = target,
        .optimize = optimize,
    });
    exe.addModule("zap", zap.module("zap"));
    exe.linkLibrary(zap.artifact("facil.io"));

    // Copy `share/` dir.
    b.installDirectory(.{
        .source_dir = std.Build.LazyPath{ .path = main_path.path ++ "/share" },
        .install_dir = .{ .prefix = {} },
        .install_subdir = "share",
    });

    // Get tailwind
    const tailwindcss_path = ".build/tailwindcss";
    const tailwindss_uri = "https://github.com/tailwindlabs/tailwindcss/releases/download/v3.3.5/tailwindcss-linux-arm64";
    retrieveFile(b, tailwindss_uri, tailwindcss_path) catch {
        @panic("Could not download tailwindcss.");
    };

    // Define `run` command.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.cwd = b.install_prefix;
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    //Tests
    const unit_tests = b.addTest(.{
        .root_source_file = root_source_file,
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

fn retrieveFile(b: *std.Build, uri: []const u8, dest_path: []const u8) !void {
    const cwd = std.fs.cwd();
    if (cwd.access(dest_path, .{})) {
        return;
    } else |err| {
        switch (err) {
            std.os.AccessError.FileNotFound => {},
            else => return err,
        }
    }

    // Create the destination directory if it doesn't exist;
    if (std.fs.path.dirname(dest_path)) |dest_dir_path| {
        try cwd.makePath(dest_dir_path);
    }

    _ = b.exec(&.{ "curl", "-L", uri, "-o", dest_path });
    const file = try cwd.openFile(dest_path, .{});
    defer file.close();
    try file.chmod(0o754);
}

fn graveyard(a: std.mem.Allocator, the_real_uri: std.Uri, dest_path: []const u8) !void {
    const cwd = std.fs.cwd();
    var client = std.http.Client{ .allocator = a };
    defer client.deinit();

    var headers = std.http.Headers.init(a);
    defer headers.deinit();

    var req = try client.request(.GET, the_real_uri, headers, .{});
    defer req.deinit();
    try req.start();
    try req.wait();

    var file = try cwd.createFile(dest_path, .{});

    var buffer: [4096]u8 = undefined;
    var reader = req.reader();
    var writer = file.writer();

    while (true) {
        const read_len = try reader.read(&buffer);
        if (read_len == 0)
            break;
        var index: usize = 0;
        while (index < read_len) {
            index += try writer.write(buffer[index..read_len]);
        }
    }
}
