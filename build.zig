const std = @import("std");

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

    // Define `run` command.
    const run_cmd = b.addRunArtifact(exe);
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
