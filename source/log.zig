const std: type = @import("std");
const builtin: type = @import("builtin");
const time: type = @import("time.zig");

pub fn print(level: std.log.Level,comptime format: []const u8,arguments: anytype) void {
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
    const timestampSlice: []const u8 = time.formatTime(&timestampBuffer,time.getLocalTimestamp());
    
    const formattedMessage: []const u8 = std.fmt.allocPrint(std.heap.page_allocator,format,arguments) catch unreachable;
    
    const linePrefix: []u8 = std.fmt.allocPrint(std.heap.page_allocator,"{s} {s} ",.{timestampSlice,levelSlice}) catch unreachable;
    
    const outputSize: usize = getValue: {
        var value: usize = 0;
        
        value += formattedMessage.len;
        
        for (formattedMessage) |character| {
            if (std.mem.eql(u8,&.{character},"\n")) {
                value += linePrefix.len;
            }
        }
        
        break :getValue value;
    };
    
    var output: []u8 = std.heap.page_allocator.alloc(u8,outputSize) catch unreachable;
    defer std.heap.page_allocator.free(output);
    
    var writeIndex: usize = 0;
    
    for (formattedMessage) |character| {
        if (std.mem.eql(u8,&.{character},"\n")) {
            output[writeIndex] = '\n';
            writeIndex += 1;
            
            std.mem.copyForwards(u8,output[writeIndex..],linePrefix);
            writeIndex += linePrefix.len;
        } else {
            output[writeIndex] = character;
            writeIndex += 1;
        }
    }

    var stdoutBuffer: [512]u8 = undefined;
    var stdoutWriter: std.fs.File.Writer = std.fs.File.stdout().writer(&stdoutBuffer);
    var stdoutWriterInterface: *std.Io.Writer = &stdoutWriter.interface;
    defer stdoutWriterInterface.flush() catch unreachable;
    
    stdoutWriterInterface.print("{s}{s}{s}{s}\n",.{colorCode,linePrefix,output,colorCodeEnd}) catch unreachable;
}

pub fn debug(comptime format: []const u8,arguments: anytype) void {
    if (builtin.mode == .Debug) {
        print(.debug,format,arguments);
    }
}

pub fn info(comptime format: []const u8,arguments: anytype) void {
    print(.info,format,arguments);
}

pub fn warn(comptime format: []const u8,arguments: anytype) void {
    print(.warn,format,arguments);
}

pub fn err(comptime format: []const u8,arguments: anytype) void {
    print(.err,format,arguments);
}
