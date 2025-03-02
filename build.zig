const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //////////
    // Modules

    // Common
    const module_common = b.addModule("common", .{
        .root_source_file = b.path("src/common.zig"),
        .target = target,
        .optimize = optimize,
    });

    // AC3
    const module_ac3 = b.addModule("ac3", .{
        .root_source_file = b.path("src/ac3.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Min Conflicts
    const module_min_conflicts = b.addModule("min-conflicts", .{
        .root_source_file = b.path("src/min-conflicts.zig"),
        .target = target,
        .optimize = optimize,
    });

    /////////////
    // Unit Tests

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/constraint-solving.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    ///////////
    // Examples

    // Example - AC3
    const exe_ac3 = b.addExecutable(.{
        .name = "example-ac3",
        .root_source_file = b.path("example/example-ac3.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_ac3.root_module.addImport("ac3", module_ac3);
    exe_ac3.root_module.addImport("common", module_common);

    b.installArtifact(exe_ac3);
    const run_cmd_ac3 = b.addRunArtifact(exe_ac3);
    run_cmd_ac3.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd_ac3.addArgs(args);
    }
    const step_name_ac3 = "run-ac3";
    const run_step_ac3 = b.step(step_name_ac3, "Run the AC3 example");
    run_step_ac3.dependOn(&run_cmd_ac3.step);

    // Example - Min Conflicts
    const exe_min_conflicts = b.addExecutable(.{
        .name = "example-min-conflicts",
        .root_source_file = b.path("example/example-min-conflicts.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_min_conflicts.root_module.addImport("min-conflicts", module_min_conflicts);
    exe_min_conflicts.root_module.addImport("common", module_common);

    b.installArtifact(exe_min_conflicts);
    const run_cmd_min_conflicts = b.addRunArtifact(exe_min_conflicts);
    run_cmd_min_conflicts.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd_min_conflicts.addArgs(args);
    }
    const step_name_min_conflicts = "run-min-conflicts";
    const run_step_min_conflicts = b.step(step_name_min_conflicts, "Run the Min Conflicts example");
    run_step_min_conflicts.dependOn(&run_cmd_min_conflicts.step);

    ////////////////
    // Generate docs

    // Docs - Common
    const lib_common = b.addStaticLibrary(.{
        .name = "common",
        .root_source_file = b.path("src/common.zig"),
        .target = target,
        .optimize = optimize,
    });
    const docs_common = b.addInstallDirectory(.{
        .source_dir = lib_common.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs/common",
    });
    // Docs - AC3
    const lib_ac3 = b.addStaticLibrary(.{
        .name = "ac3",
        .root_source_file = b.path("src/ac3.zig"),
        .target = target,
        .optimize = optimize,
    });
    const docs_ac3 = b.addInstallDirectory(.{
        .source_dir = lib_ac3.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs/ac3",
    });
    // Docs - Min Conflicts
    const lib_min_conflicts = b.addStaticLibrary(.{
        .name = "min-conflicts",
        .root_source_file = b.path("src/min-conflicts.zig"),
        .target = target,
        .optimize = optimize,
    });
    const docs_min_conflicts = b.addInstallDirectory(.{
        .source_dir = lib_min_conflicts.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs/min-conflicts",
    });

    b.getInstallStep().dependOn(&docs_common.step);
    b.getInstallStep().dependOn(&docs_ac3.step);
    b.getInstallStep().dependOn(&docs_min_conflicts.step);
}
