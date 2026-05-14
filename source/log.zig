const std: type = @import("std");
const builtin: type = @import("builtin");
const time: type = @import("time.zig");

pub fn print(io: std.Io,level: std.log.Level,comptime format: []const u8,arguments: anytype) void {
    var levelSlice: []const u8 = undefined;
    var colorCode: []const u8 = undefined;
    const colorCodeEnd: []const u8 = "\x1b[0m";
    
    switch (level) {
        .debug => {
            levelSlice = "[DEBUG]";
            colorCode = "\x1b[36m";
        },
        .info => {
            levelSlice = "[INFO] ";
            colorCode = "\x1b[32m";
        },
        .warn => {
            levelSlice = "[WARN] ";
            colorCode = "\x1b[33m";
        },
        .err => {
            levelSlice = "[ERROR]";
            colorCode = "\x1b[31m";
        }
    }
    
    var timestampBuffer: time.FormattedTimestampBuffer = undefined;
    const timestampSlice: []const u8 = time.formatTime(&timestampBuffer,time.getLocalTimestamp(io));
    
    const formattedMessage: []const u8 = std.fmt.allocPrint(std.heap.page_allocator,format,arguments) catch unreachable;
    
    const linePrefix: []u8 = std.fmt.allocPrint(std.heap.page_allocator,"{s} {s} ",.{timestampSlice,levelSlice}) catch unreachable;
    
    var stdoutBuffer: [512]u8 = undefined;
    var stdoutWriter: std.Io.File.Writer = std.Io.File.stdout().writer(io,&stdoutBuffer);
    var stdoutWriterInterface: *std.Io.Writer = &stdoutWriter.interface;
    defer stdoutWriterInterface.flush() catch unreachable;
    
    stdoutWriterInterface.print("{s}{s}",.{colorCode,linePrefix}) catch unreachable;
    
    var start: usize = 0;
    
    for (formattedMessage,0..) |character,index| {
        if (character == '\n') {
            if (index > start) {
                _ = stdoutWriterInterface.writeAll(formattedMessage[start..index]) catch unreachable;
            }
            
            stdoutWriterInterface.print("\n{s}",.{linePrefix}) catch unreachable;
            start = index + 1;
        }
    }
    
    if (start < formattedMessage.len) {
        _ = stdoutWriterInterface.writeAll(formattedMessage[start..]) catch unreachable;
    }
    
    stdoutWriterInterface.print("{s}\n",.{colorCodeEnd}) catch unreachable;
}

pub fn debug(io: std.Io,comptime format: []const u8,arguments: anytype) void {
    if (builtin.mode == .Debug) {
        print(io,.debug,format,arguments);
    }
}

pub fn info(io: std.Io,comptime format: []const u8,arguments: anytype) void {
    print(io,.info,format,arguments);
}

pub fn warn(io: std.Io,comptime format: []const u8,arguments: anytype) void {
    print(io,.warn,format,arguments);
}

pub fn err(io: std.Io,comptime format: []const u8,arguments: anytype) void {
    print(io,.err,format,arguments);
}
