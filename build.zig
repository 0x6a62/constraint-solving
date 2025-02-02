const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("ac3", .{
        .root_source_file = b.path("src/ac3.zig"),
        .target = target,
        .optimize = optimize,
    });

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/ac3.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.root_module.addImport("ac3", module);
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Example
    const exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = b.path("example/example.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("ac3", module);

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const step_name = "run";
    const run_step = b.step(step_name, "Run the example");
    run_step.dependOn(&run_cmd.step);

    // generate docs
    const lib = b.addStaticLibrary(.{
        .name = "ac3",
        .root_source_file = b.path("src/ac3.zig"),
        .target = target,
        .optimize = optimize,
    });
    const docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    b.getInstallStep().dependOn(&docs.step);
}
