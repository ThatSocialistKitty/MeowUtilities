const std: type = @import("std");

pub fn build(b: *std.Build) void {
    const target: std.Build.ResolvedTarget = b.standardTargetOptions(.{});
    const optimize: std.builtin.OptimizeMode = b.standardOptimizeOption(.{});

    const mainModule: *std.Build.Module = b.addModule("main",.{
        .root_source_file = b.path("source/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    mainModule.link_libc = true;
    
    mainModule.linkSystemLibrary("zlib-ng",.{});
    
    // TODO: Get dis working :3
    
    // const dependenciesLibrary: *std.Build.Step.Compile = b.addLibrary(.{
    //     .name = "dependencies",
    //     .root_module = b.createModule(.{
    //         .target = target,
    //         .optimize = optimize,
    //         .link_libc = true,
    //         .pic = true
    //     })
    // });
    // 
    // {
    //     dependenciesLibrary.addIncludePath(b.path("dependencies/zlib-ng"));
    //     
    //     dependenciesLibrary.root_module.addCSourceFiles(.{
    //         .root = b.path("dependencies/zlib-ng"),
    //         .files = &.{
    //             "adler32.c",
    //             "crc32.c",
    //             "deflate.c",
    //             "infback.c",
    //             "inflate.c",
    //             "inftrees.c",
    //             "trees.c",
    //             "zutil.c",
    //             "compress.c",
    //             "uncompr.c",
    //             "functable.c",
    //             "cpu_features.c"
    //         },
    //         .flags = &.{
    //             "-DHAVE_SYS_TYPES_H",
    //             "-DHAVE_STDINT_H",
    //             "-DHAVE_STDDEF_H",
    //             "-DZ_HAVE_UNISTD_H",
    //             "-fPIC"
    //         }
    //     });
    //     
    //     dependenciesLibrary.installHeadersDirectory(b.path("dependencies/zlib-ng"),"",.{
    //         .include_extensions = &.{
    //             "zconf.h",
    //             "zlib.h"
    //         }
    //     });
    // }
    // 
    // mainModule.linkLibrary(dependenciesLibrary);
}
