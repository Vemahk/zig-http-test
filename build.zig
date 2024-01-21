const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const main_path = std.Build.LazyPath{ .path = "src" };

    const root_source_file = std.Build.LazyPath{ .path = main_path.path ++ "/main.zig" };
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const exe = b.addExecutable(.{
        .name = "http-test",
        .root_source_file = root_source_file,
        .target = target,
        .optimize = optimize,
        .main_pkg_path = main_path,
    });
    const exe_opts = b.addOptions();
    //exe_opts.addOption(bool, "help", b.option(bool, "help", "a test value") orelse false);
    exe.addOptions("build_flags", exe_opts);

    // Add dependencies
    const mustache = b.dependency("mustache", .{
        .target = target,
        .optimize = optimize,
    });
    exe.addModule("mustache", mustache.module("mustache"));

    const zap = b.dependency("zap", .{
        .target = target,
        .optimize = optimize,
        //.openssl = true,
    });
    exe.addModule("zap", zap.module("zap"));
    exe.linkLibrary(zap.artifact("facil.io"));
    b.installArtifact(exe);

    // Copy `share/` dir.
    var share_dir = b.addInstallDirectory(.{
        .source_dir = std.Build.LazyPath{ .path = main_path.path ++ "/share" },
        .install_dir = .{ .prefix = {} },
        .install_subdir = "share",
    });
    b.getInstallStep().dependOn(&share_dir.step);

    var tw_pull = fnStep(b, "tailwind-pull", "Download TailwindCSS", prepareTailwind);
    const tw_build = b.addSystemCommand(&[_][]const u8{
        ".build/tailwindcss",
        "-c",
        ".config/tailwind.config.js",
        "-i",
        "./src/share/static/styles/tailwind.src.css",
        "-o",
        "./zig-out/share/static/styles/tailwind.css",
    });
    tw_build.step.dependOn(tw_pull);
    tw_build.step.dependOn(&share_dir.step);
    _ = addStep(b, "tailwind", "Build TailwindCSS", &tw_build.step);

    // Define `run` command.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.cwd = b.install_prefix;
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.step.dependOn(&tw_build.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    _ = addStep(b, "run", "Run the app", &run_cmd.step);

    //Tests
    const unit_tests = b.addTest(.{
        .root_source_file = root_source_file,
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    _ = addStep(b, "test", "Run unit tests", &run_unit_tests.step);
}

fn prepareTailwind(step: *std.Build.Step, progress: *std.Progress.Node) !void {
    var p = progress.start("Downloading TailwindCSS", 1);
    defer p.end();

    // Get tailwind
    const b = step.owner;
    const tailwindcss_path = ".build/tailwindcss";
    const tailwindss_uri = "https://github.com/tailwindlabs/tailwindcss/releases/download/v3.3.5/tailwindcss-linux-arm64";
    try retrieveFile(b, tailwindss_uri, tailwindcss_path);
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

    //TODO: figure out windows permissions?
    try file.chmod(0o500);
}

const MakeFn = std.Build.Step.MakeFn;
fn fnStep(b: *std.Build, name: []const u8, description: []const u8, make_fn: MakeFn) *std.Build.Step {
    var step = b.step(name, description);
    step.makeFn = make_fn;
    return step;
}

fn addStep(b: *std.Build, name: []const u8, description: []const u8, other: *std.Build.Step) *std.Build.Step {
    var step = b.step(name, description);
    step.dependOn(other);
    return step;
}
