const std: type = @import("std");

pub fn openSelfDirectory(flags: std.fs.Dir.OpenOptions) !std.fs.Dir {
    const selfDirectoryPath: []const u8 = try std.fs.selfExeDirPathAlloc(std.heap.page_allocator);
    defer std.heap.page_allocator.free(selfDirectoryPath);
    
    return try std.fs.openDirAbsolute(selfDirectoryPath,flags);
}
