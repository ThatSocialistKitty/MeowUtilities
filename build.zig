const std: type = @import("std");

pub fn build(builder: *std.Build) void {
    const target: std.Build.ResolvedTarget = builder.standardTargetOptions(.{});
    const optimize: std.builtin.OptimizeMode = builder.standardOptimizeOption(.{});

    const mainModule: *std.Build.Module = builder.addModule("main",.{
        .root_source_file = builder.path("source/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    mainModule.link_libc = true;
    
    mainModule.linkSystemLibrary("zlib-ng",.{});
    
    // TODO: Get dis working :3
    
    // const dependenciesLibrary: *std.Build.Step.Compile = builder.addLibrary(.{
    //     .name = "dependencies",
    //     .root_module = builder.createModule(.{
    //         .target = target,
    //         .optimize = optimize,
    //         .link_libc = true,
    //         .pic = true
    //     })
    // });
    // 
    // {
    //     dependenciesLibrary.addIncludePath(builder.path("dependencies/zlib-ng"));
    //     
    //     dependenciesLibrary.root_module.addCSourceFiles(.{
    //         .root = builder.path("dependencies/zlib-ng"),
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
    //     dependenciesLibrary.installHeadersDirectory(builder.path("dependencies/zlib-ng"),"",.{
    //         .include_extensions = &.{
    //             "zconf.h",
    //             "zlib.h"
    //         }
    //     });
    // }
    // 
    // mainModule.linkLibrary(dependenciesLibrary);
}
