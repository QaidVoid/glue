const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    const core_mod = b.createModule(.{
        .root_source_file = b.path("src/core/main.zig"),
    });
    const tui_mod = b.createModule(.{
        .root_source_file = b.path("src/tui/main.zig"),
    });

    const app_mod = b.createModule(.{
        .root_source_file = b.path("src/app/main.zig"),
    });
    app_mod.addImport("core", core_mod);
    app_mod.addImport("tui", tui_mod);

    core_mod.addImport("core", core_mod);

    tui_mod.addImport("core", core_mod);
    tui_mod.addImport("app", app_mod);
    tui_mod.addImport("tui", tui_mod);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // .strip = true,
        // .single_threaded = true,
        // .unwind_tables = .none,
    });
    exe_mod.addImport("app", app_mod);
    exe_mod.addImport("core", core_mod);
    exe_mod.addImport("tui", tui_mod);

    const exe = b.addExecutable(.{
        .name = "glue",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
