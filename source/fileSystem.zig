const std: type = @import("std");

pub fn openExecutableDirectory(io: std.Io,flags: std.Io.Dir.OpenOptions) !std.Io.Dir {
    var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const pathLength: usize = try std.process.executableDirPath(io,path[0..]);
    return try .openDirAbsolute(io,path[0..pathLength],flags);
}
