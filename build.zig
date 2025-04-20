const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const ghmath = b.dependency("ghmath", .{ .optimize = optimize, .target = target });

    const ghgrid_mod = b.addModule("ghgrid", .{
        .root_source_file = b.path("src/root.zig"),
        .optimize = optimize,
        .target = target,
    });

    ghgrid_mod.addImport("ghmath", ghmath.module("ghmath"));
}
