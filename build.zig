const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // library
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/ac3.zig"),
        .target = target,
        .optimize = optimize,
    });

    // example usage
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("example/example.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add library dependency to example exe
    exe_mod.addImport("ac3", lib_mod);

    // Creates a `std.Build.Step.Compile` for library
    const lib = b.addStaticLibrary(.{
        .name = "ac3",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    // This creates a `std.Build.Step.Compile` for example
    const exe = b.addExecutable(.{
        .name = "example",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step `zig build run`
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // This creates a test step `zig build test`
    const test_step = b.step("test", "Run unit tests");
    _ = run_exe_unit_tests.step;
    test_step.dependOn(&run_lib_unit_tests.step);
    //test_step.dependOn(&run_exe_unit_tests.step);

    // generate docs
    const docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    b.getInstallStep().dependOn(&docs.step);
}
