const std = @import("std");
const builtin = @import("builtin");

const targets: []const std.Target.Query = &.{
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
};

pub fn build(b: *std.Build) void {
    const main_path = "src";

    const root_source_file = b.path(main_path ++ "/main.zig");
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const exe = b.addExecutable(.{
        .name = "http-test",
        .root_source_file = root_source_file,
        .target = target,
        .optimize = optimize,
    });

    // Add dependencies
    const mustache = b.dependency("mustache", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("mustache", mustache.module("mustache"));

    const zap = b.dependency("zap", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zap", zap.module("zap"));
    exe.linkLibrary(zap.artifact("facil.io"));
    b.installArtifact(exe);

    // Copy `share/` dir.
    var share_dir = b.addInstallDirectory(.{
        .source_dir = b.path(main_path ++ "/share"),
        .install_dir = .{ .bin = {} },
        .install_subdir = "share",
    });
    b.getInstallStep().dependOn(&share_dir.step);

    const tw_pull = fnStep(b, "tailwind-pull", "Download TailwindCSS", prepareTailwind);
    const tw_build = b.addSystemCommand(&[_][]const u8{
        ".build/tailwindcss",
        "-c",
        ".config/tailwind.config.js",
        "-i",
        "./src/share/static/styles/tailwind.src.css",
        "-o",
        "./zig-out/bin/share/static/styles/tailwind.css",
    });
    tw_build.step.dependOn(tw_pull);
    tw_build.step.dependOn(&share_dir.step);
    _ = addStep(b, "tailwind", "Build TailwindCSS", &tw_build.step);

    const sus = b.getInstallPath(.{ .bin = {} }, "");
    const kill_me = std.Build.LazyPath{ .cwd_relative = sus };

    // Define `run` command.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.setCwd(kill_me);
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

fn prepareTailwind(step: *std.Build.Step, progress: std.Progress.Node) !void {
    const version = "3.4.4";
    const tailwindcss_path = ".build/tailwindcss";
    const tailwind_download_root = "https://github.com/tailwindlabs/tailwindcss/releases/download";

    var p = progress.start("Downloading TailwindCSS v" ++ version, 1);
    defer p.end();

    // Get tailwind
    const b = step.owner;
    const a = b.allocator;

    const builder_triple = try b.graph.host.result.linuxTriple(a);

    const tw_targets = std.StaticStringMap([]const u8).initComptime(.{
        .{ "x86_64-linux-gnu", "tailwindcss-linux-x64" },
        .{ "aarch64-linux-gnu", "tailwindcss-linux-arm64" },
    });

    const tailwindcss_uri = try std.fmt.allocPrint(a, "{s}/v{s}/{s}", .{
        tailwind_download_root,
        version,
        tw_targets.get(builder_triple) orelse unreachable,
    });
    defer a.free(tailwindcss_uri);

    try retrieveFile(b, tailwindcss_uri, tailwindcss_path);
}

fn retrieveFile(b: *std.Build, uri: []const u8, dest_path: []const u8) !void {
    const cwd = std.fs.cwd();
    if (cwd.access(dest_path, .{})) {
        return;
    } else |err| {
        switch (err) {
            std.posix.AccessError.FileNotFound => {},
            else => return err,
        }
    }

    // Create the destination directory if it doesn't exist;
    if (std.fs.path.dirname(dest_path)) |dest_dir_path| {
        try cwd.makePath(dest_dir_path);
    }

    _ = b.run(&.{ "curl", "-L", uri, "-o", dest_path });
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
