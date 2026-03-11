const std: type = @import("std");

pub fn build(b: *std.Build) void {
    const target: std.Build.ResolvedTarget = b.standardTargetOptions(.{});
    const optimize: std.builtin.OptimizeMode = b.standardOptimizeOption(.{});
    
    const mainModule: *std.Build.Module = b.addModule("main",.{
        .root_source_file = b.path("source/main.zig"),
        .target = target,
        .optimize = optimize
    });
    
    mainModule.link_libc = true;
}
