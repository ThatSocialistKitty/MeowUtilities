const std: type = @import("std");
const fileSystem: type = @import("fileSystem.zig");
const zlib: type = @cImport({
    @cInclude("zlib-ng.h");
});

pub fn EventBus(comptime EventData: type) type {
    std.debug.assert(std.meta.activeTag(@typeInfo(EventData)) == .@"union");
    
    return struct {
        allocator: std.mem.Allocator = undefined,
        events: std.ArrayList(Event) = .empty,
        pollingIndex: usize = 0,
        
        pub const Event: type = struct {
            consume: bool = false,
            data: EventData
        };
        
        pub fn create(allocator: std.mem.Allocator) @This() {
            var self: @This() = .{};
            self.allocator = allocator;
            return self;
        }
        
        pub fn destroy(self: *@This()) void {
            self.events.deinit(self.allocator);
        }
        
        pub fn poll(self: *@This()) ?*Event {
            const event: ?*Event = if (self.pollingIndex < self.events.items.len) &self.events.items[self.pollingIndex] else null;
            
            if (event != null) {
                if (event.?.*.consume) {
                    _ = self.events.orderedRemove(0);
                    return null;
                }
                
                self.pollingIndex += 1;
            } else {
                if (self.pollingIndex >= self.events.items.len) {
                    self.pollingIndex = 0;
                    return null;
                }
            }
            
            return event;
        }
        
        pub fn append(self: *@This(),eventData: EventData) void {
            self.events.append(self.allocator,.{
                .data = eventData
            }) catch unreachable;
        }
    };
}

pub const Image: type = struct {
    allocator: std.mem.Allocator = undefined,
    pixels: []Pixel = undefined,
    metadata: Metadata = .{},
    
    pub const Metadata: type = struct {
        format: Format = undefined,
        dimensions: [2]u32 = undefined,
        resolution: u32 = undefined,
        size: usize = undefined,
        tags: ?[]const []const u8 = null
    };
    
    const Pixel: type = struct {
        red: u8,
        green: u8,
        blue: u8,
        alpha: u8
    };
    
    const Format: type = enum {
        Png
    };
    
    const formatSignatures: []const []const u8 = &.{
        &.{0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a}
    };
    
    fn decodePng(allocator: std.mem.Allocator,fileData: []const u8,output: struct {pixels: *[]Pixel,metadata: *Metadata}) !void {
        const ChunkKind: type = enum {
            IHDR, // Header
            IDAT, // Compressed scanlines
            tEXt, // Tags
            IEND // End
        };
        
        const Chunk: type = struct {
            dataLength: u32,
            kind: ChunkKind,
            data: []const u8,
            checksum: u32
        };
        
        var compressedScanlines: std.ArrayList(u8) = .empty;
        defer compressedScanlines.deinit(allocator);
        
        var tags: std.ArrayList([]const u8) = .empty;
        defer tags.deinit(allocator);
        
        var channelCount: u8 = undefined;
        var bitDepth: u8 = undefined;
        var pixelSize: u8 = undefined;
        
        // Parse chunks
        
        
            var fileDataReader: std.Io.Reader = .fixed(fileData);
            
            fileDataReader.toss(8);
            
            while (true) {
                var chunk = std.mem.zeroes(Chunk);
                
                chunk.dataLength = try fileDataReader.takeInt(u32,.big);
                
                var typeField: []const u8 = try fileDataReader.takeArray(4);
                
                var chunkIsRelevant: bool = false;
                
                inline for (@typeInfo(ChunkKind).@"enum".fields,0..) |field,fieldIndex| {
                    if (std.mem.eql(u8,typeField[0..],field.name)) {
                        chunk.kind = @enumFromInt(fieldIndex);
                        chunkIsRelevant = true;
                        break;
                    }
                }
                
                const dataField = try fileDataReader.take(chunk.dataLength);
                
                chunk.data = dataField;
                
                chunk.checksum = try fileDataReader.takeInt(u32,.big);
                
                if (chunkIsRelevant) {
                    // Validate checksum
                    
                    
                        var hash: std.hash.Crc32 = .init();
                        
                        hash.update(typeField[0..]);
                        hash.update(dataField[0..]);
                        
                        if (hash.final() != chunk.checksum) return error.CorruptChunkFound;
                    
                    
                    switch (chunk.kind) {
                        .IHDR => {
                            output.metadata.dimensions = .{
                                std.mem.readPackedInt(u32,chunk.data[0..4],0,.big),
                                std.mem.readPackedInt(u32,chunk.data[4..8],0,.big)
                            };
                            
                            output.metadata.resolution = output.metadata.dimensions[0] * output.metadata.dimensions[1];
                            
                            channelCount = switch (chunk.data[9]) {
                                2 => 3,
                                6 => 4,
                                else => return error.ColorTypeNotSupported
                            };
                            
                            bitDepth = chunk.data[8];
                            pixelSize = (bitDepth / 8) * channelCount;
                            
                            output.metadata.size = @sizeOf(Pixel) * output.metadata.resolution;
                        },
                        .IDAT => compressedScanlines.appendSlice(allocator,chunk.data) catch unreachable,
                        .tEXt => tags.append(allocator,allocator.dupe(u8,chunk.data) catch unreachable) catch unreachable,
                        .IEND => break
                    }
                }
            }
        
        
        if (tags.items.len > 0) {
            output.metadata.tags = tags.toOwnedSlice(allocator) catch unreachable;
        }
        
        const scanlines: []u8 = allocator.alloc(u8,((output.metadata.dimensions[0] * channelCount * bitDepth + 7) / 8 + 1) * output.metadata.dimensions[1]) catch unreachable;
        defer allocator.free(scanlines);
        
        var bytesWritten = scanlines.len;
        
        if (zlib.zng_uncompress(scanlines.ptr,&bytesWritten,compressedScanlines.items.ptr,compressedScanlines.items.len) != zlib.Z_OK) return error.DecompressionFailure;
        
        output.pixels.* = allocator.alloc(Pixel,output.metadata.dimensions[0] * output.metadata.dimensions[1]) catch unreachable;
        
        const Filter: type = enum {
            None,
            Sub,
            Up,
            Average,
            Paeth
        };
        
        const scanlineDataLength: usize = output.metadata.dimensions[0] * channelCount;
        
        var buffer = try allocator.alloc(u8,scanlineDataLength * 2);
        defer allocator.free(buffer);
        
        @memset(buffer,0);
        
        var unfilteredScanline = buffer[0..scanlineDataLength];
        const previousUnfilteredScanline = buffer[scanlineDataLength..scanlineDataLength * 2];
        
        for (0..output.metadata.dimensions[1]) |y| {
            const rowStartIndex: usize = y * (scanlineDataLength + 1);
            const filter: Filter = @enumFromInt(scanlines[rowStartIndex]);
            const scanline: []u8 = scanlines[rowStartIndex + 1..rowStartIndex + 1 + scanlineDataLength];
            
            switch (filter) {
                .None => {
                    @memcpy(unfilteredScanline,scanline);
                },
                .Sub => {
                    for (0..scanlineDataLength) |index| {
                        const left: u8 = if (index >= pixelSize) unfilteredScanline[index - pixelSize] else 0;
                        unfilteredScanline[index] = scanline[index] +% left;
                    }
                },
                .Up => {
                    for (0..scanlineDataLength) |index| {
                        unfilteredScanline[index] = scanline[index] +% previousUnfilteredScanline[index];
                    }
                },
                .Average => {
                    for (0..scanlineDataLength) |index| {
                        const left: u16 = if (index >= pixelSize) @as(u16,unfilteredScanline[index - pixelSize]) else 0;
                        const up: u16 = @as(u16,previousUnfilteredScanline[index]);
                        
                        unfilteredScanline[index] = scanline[index] +% @as(u8,@intCast((left + up) >> 1));
                    }
                },
                .Paeth => {
                    for (0..scanlineDataLength) |index| {
                        const a: i32 = if (index >= pixelSize) unfilteredScanline[index - pixelSize] else 0;
                        const b: i32 = previousUnfilteredScanline[index];
                        const c: i32 = if (index >= pixelSize) previousUnfilteredScanline[index - pixelSize] else 0;
                        
                        const p: i32 = a + b - c;
                        
                        const pa: i32 = @intCast(@abs(p - a));
                        const pb: i32 = @intCast(@abs(p - b));
                        const pc: i32 = @intCast(@abs(p - c));
                        
                        const prediction: i32 = if (pa <= pb and pa <= pc) a else if (pb <= pc) b else c;
                        
                        unfilteredScanline[index] = scanline[index] +% @as(u8,@intCast(prediction));
                    }
                }
            }
            
            for (0..output.metadata.dimensions[0]) |x| {
                const scanlinePixelIndex: usize = x * channelCount;
                
                output.pixels.*[y * output.metadata.dimensions[0] + x] = .{
                    .red = unfilteredScanline[scanlinePixelIndex],
                    .green = unfilteredScanline[scanlinePixelIndex + 1],
                    .blue = unfilteredScanline[scanlinePixelIndex + 2],
                    .alpha = if (channelCount == 4) unfilteredScanline[scanlinePixelIndex + 3] else 255
                };
            }
            
            @memcpy(previousUnfilteredScanline,unfilteredScanline);
        }
    }
    
    pub fn create(allocator: std.mem.Allocator,fileData: []const u8) !@This() {
        var self: @This() = .{};
        
        self.allocator = allocator;
        
        // Select format
        
        
            var formatAssigned: bool = false;
            
            inline for (formatSignatures,0..) |signature,signatureIndex| {
                if (std.mem.startsWith(u8,fileData,signature)) {
                    self.metadata.format = @enumFromInt(@typeInfo(Format).@"enum".fields[signatureIndex].value);
                    formatAssigned = true;
                    break;
                }
            }
            
            if (!formatAssigned) {
                return error.UnsupportedFormat;
            }
        
        
        switch (self.metadata.format) {
            .Png => try decodePng(allocator,fileData,.{
                .pixels = &self.pixels,
                .metadata = &self.metadata
            })
        }
        
        return self;
    }
    
    pub fn createFromFile(allocator: std.mem.Allocator,io: std.Io,path: []const u8) !@This() {
        const executableDirectory: std.Io.Dir = try fileSystem.openExecutableDirectory(io,.{});
        defer executableDirectory.close(io);
        
        const fileContents: []u8 = try executableDirectory.readFileAlloc(io,path,allocator,.unlimited);
        defer allocator.free(fileContents);
        
        return try .create(allocator,fileContents);
    }
    
    pub fn destroy(self: *@This()) void {
        self.allocator.free(self.pixels);
        
        if (self.metadata.tags != null) {
            for (self.metadata.tags.?) |tag| {
                self.allocator.free(tag);
            }
            
            self.allocator.free(self.metadata.tags.?);
        }
    }
    
    pub fn getPixels(self: @This()) []const Pixel {
        return self.pixels;
    }
    
    pub fn getMetadata(self: @This()) Metadata {
        return self.metadata;
    }
};

pub const GlbParser: type = struct {
    pub const Node: type = undefined;
    
    pub const Scene: type = []Node;
    
    pub fn create(allocator: std.mem.Allocator,path: []const u8) @This() {
        _ = allocator; _ = path;
        return .{};
    }
};
