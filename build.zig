const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    // Dependencies
    const ghmath_dep = b.dependency("ghmath", .{
        .target = target,
        .optimize = optimize,
    });
    const ghdbg_dep = b.dependency("ghdbg", .{
        .target = target,
        .optimize = optimize,
    });

    _ = b.addModule("ghgrid", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "ghmath",
                .module = ghmath_dep.module("ghmath"),
            },

            .{
                .name = "ghdbg",
                .module = ghdbg_dep.module("ghdbg"),
            },
        },
    });
}
