const std: type = @import("std");
const fileSystem: type = @import("fileSystem.zig");
const zlib: type = @cImport({
    @cInclude("zlib-ng.h");
});

pub fn EventBus(comptime EventData: type) type {
    std.debug.assert(std.meta.activeTag(@typeInfo(EventData)) == .@"union");
    
    return struct {
        pub const Event: type = struct {
            consume: bool = false,
            data: EventData
        };
        
        const Implementation: type = struct {
            allocator: std.mem.Allocator,
            events: std.ArrayList(Event),
            pollingIndex: usize
        };
        
        pub fn create(allocator: std.mem.Allocator) *@This() {
            const eventBus: *Implementation = allocator.create(Implementation) catch unreachable;
            
            eventBus.allocator = allocator;
            eventBus.events = .empty;
            eventBus.pollingIndex = 0;
            
            return @ptrCast(eventBus);
        }
        
        pub fn destroy(self: *@This()) void {
            const eventBus: *Implementation = @ptrCast(@alignCast(self));
            
            eventBus.events.deinit(eventBus.allocator);
            eventBus.allocator.destroy(eventBus);
        }
        
        pub fn poll(self: *@This()) ?*Event {
            const eventBus: *Implementation = @ptrCast(@alignCast(self));
            
            const event: ?*Event = if (eventBus.pollingIndex < eventBus.events.items.len) &eventBus.events.items[eventBus.pollingIndex] else null;
            
            if (event != null) {
                if (event.?.*.consume) {
                    _ = eventBus.events.orderedRemove(0);
                    return null;
                }
                
                eventBus.pollingIndex += 1;
            } else {
                if (eventBus.pollingIndex >= eventBus.events.items.len) {
                    eventBus.pollingIndex = 0;
                    return null;
                }
            }
            
            return event;
        }
        
        pub fn append(self: *@This(),eventData: EventData) void {
            const eventBus: *Implementation = @ptrCast(@alignCast(self));
            
            eventBus.events.append(eventBus.allocator,.{
                .data = eventData
            }) catch unreachable;
        }
    };
}

pub const Image: type = struct {
    const Format: type = enum {
        Png
    };
    
    const formatSignatures: []const []const u8 = &.{
        &.{0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a}
    };
    
    pub const Metadata: type = struct {
        format: Format,
        dimensions: [2]u32,
        resolution: u32,
        size: usize,
        tags: ?[]const []const u8
    };
    
    const Pixel: type = struct {
        red: u8,
        green: u8,
        blue: u8,
        alpha: u8
    };
    
    const Implementation: type = struct {
        allocator: std.mem.Allocator,
        pixels: []Pixel,
        metadata: Metadata
    };
    
    fn decodePng(allocator: std.mem.Allocator,imageData: []const u8,output: struct {pixels: *[]Pixel,metadata: *Metadata}) !void {
        const ChunkKind: type = enum {
            IHDR, // Header
            IDAT, // Compressed scanlines
            tEXt, // Tags
            IEND // End of image
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
        
            var byteIndex: usize = 8;
            const fieldSize: usize = 4;
            
            while (true) {
                var chunk = std.mem.zeroes(Chunk);
                
                chunk.dataLength = std.mem.readPackedInt(u32,imageData[byteIndex..byteIndex + fieldSize],0,.big);
                
                byteIndex += fieldSize;
                
                const typeField: []const u8 = imageData[byteIndex..byteIndex + fieldSize];
                
                var chunkIsRelevant: bool = false;
                
                inline for (@typeInfo(ChunkKind).@"enum".fields,0..) |field,fieldIndex| {
                    if (std.mem.eql(u8,imageData[byteIndex..byteIndex + fieldSize],field.name)) {
                        chunk.kind = @enumFromInt(fieldIndex);
                        chunkIsRelevant = true;
                        break;
                    }
                }
                
                byteIndex += fieldSize;
                
                const dataField: []const u8 = imageData[byteIndex..byteIndex + chunk.dataLength];
                
                chunk.data = imageData[byteIndex..byteIndex + chunk.dataLength];
                
                byteIndex += chunk.dataLength;
                
                chunk.checksum = std.mem.readPackedInt(u32,imageData[byteIndex..byteIndex + fieldSize],0,.big);
                
                byteIndex += fieldSize;
                
                if (chunkIsRelevant) {
                    // Validate checksum
                    
                    
                        var hash: std.hash.Crc32 = .init();
                        
                        hash.update(typeField);
                        hash.update(dataField);
                        
                        if (hash.final() != chunk.checksum) return error.CorruptChunkFound;
                    
                    
                    switch (chunk.kind) {
                        .IHDR => {
                            output.metadata.dimensions = .{
                                std.mem.readPackedInt(u32,chunk.data[0..fieldSize],0,.big),
                                std.mem.readPackedInt(u32,chunk.data[fieldSize..fieldSize * 2],0,.big)
                            };
                            
                            output.metadata.dimensions[0] = output.metadata.dimensions[0];
                            output.metadata.dimensions[1] = output.metadata.dimensions[1];
                            
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
    
    pub fn create(allocator: std.mem.Allocator,imageData: []const u8) !*@This() {
        const image: *Implementation = allocator.create(Implementation) catch unreachable;
        
        image.allocator = allocator;
        
        {
            var formatAssigned: bool = false;
            
            inline for (formatSignatures,0..) |signature,signatureIndex| {
                if (std.mem.startsWith(u8,imageData,signature)) {
                    image.metadata.format = @enumFromInt(@typeInfo(Format).@"enum".fields[signatureIndex].value);
                    formatAssigned = true;
                    break;
                }
            }
            
            if (!formatAssigned) {
                return error.UnsupportedFormat;
            }
        }
        
        image.metadata.tags = null;
        
        switch (image.metadata.format) {
            .Png => try decodePng(allocator,imageData,.{
                .pixels = &image.pixels,
                .metadata = &image.metadata
            })
        }
        
        return @ptrCast(image);
    }
    
    pub fn createFromFile(allocator: std.mem.Allocator,path: []const u8) !*@This() {
        const imageData: []u8 = getValue: {
            var selfDirectory: std.fs.Dir = try fileSystem.openSelfDirectory(.{});
            defer selfDirectory.close();
            
            var file: std.fs.File = try selfDirectory.openFile(path,.{
                .mode = .read_only
            });
            defer file.close();
            
            var fileReaderBuffer: [256]u8 = undefined;
            break :getValue try std.Io.Reader.readAlloc(@constCast(&file.reader(&fileReaderBuffer).interface),allocator,(try file.stat()).size);
        };
        defer allocator.free(imageData);
        
        return create(allocator,imageData);
    }
    
    pub fn destroy(self: *@This()) void {
        const image: *Implementation = @ptrCast(@alignCast(self));
        
        image.allocator.free(image.pixels);
        
        if (image.metadata.tags != null) {
            for (image.metadata.tags.?) |tag| {
                image.allocator.free(tag);
            }
            
            image.allocator.free(image.metadata.tags.?);
        }
        
        image.allocator.destroy(image);
    }
    
    pub fn getPixels(self: *@This()) []const Pixel {
        const image: *Implementation = @ptrCast(@alignCast(self));
        return image.pixels;
    }
    
    pub fn getMetadata(self: *@This()) Metadata {
        const image: *Implementation = @ptrCast(@alignCast(self));
        return image.metadata;
    }
};

// var parser: GlbParser = .create(allocator,"../../source/models/roblox.glb");
// defer parser.destroy();
// 
// while (true) {
//     const element: parser.Element = try parser.next();
//     
//     switch (element) {
//         .scene => {},
//         .node => {},
//         .mesh => {},
//         .camera => {},
//         .skin => {},
//         .animation => {},
//         .end => break;
//     }
// }

// pub fn SparseSet(comptime EventData: type) type {
//     std.debug.assert(std.meta.activeTag(@typeInfo(EventData)) == .@"union");
//     
//     return opaque {
//         const Implementation: type = struct {
//             allocator: std.mem.Allocator,
//         };
//         
//         pub fn create(allocator: std.mem.Allocator) *@This() {
//             const eventBus: *Implementation = allocator.create(Implementation) catch unreachable;
//             
//             eventBus.allocator = allocator;
//             
//             return @ptrCast(eventBus);
//         }
//         
//         pub fn destroy(self: *@This()) void {
//             const eventBus: *Implementation = @ptrCast(@alignCast(self));
//             eventBus.allocator.destroy(eventBus);
//         }
//     };
// }
// 
// 
// pub fn SparseSet(
//     comptime Key: type,
//     comptime T: type,
//     comptime keyToIndex: fn (Key) usize,
// ) type {
//     return struct {
//         const Self = @This();
// 
//         allocator: std.mem.Allocator,
// 
//         dense: std.ArrayList(T),
//         dense_keys: std.ArrayList(Key),
// 
//         sparse: []usize,
// 
//         const INVALID: usize = std.math.maxInt(usize);
// 
//         pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
//             var sparse = try allocator.alloc(usize, capacity);
//             @memset(sparse, INVALID);
// 
//             return .{
//                 .allocator = allocator,
//                 .dense = std.ArrayList(T).init(allocator),
//                 .dense_keys = std.ArrayList(Key).init(allocator),
//                 .sparse = sparse,
//             };
//         }
// 
//         pub fn deinit(self: *Self) void {
//             self.dense.deinit();
//             self.dense_keys.deinit();
//             self.allocator.free(self.sparse);
//         }
// 
//         fn ensureCapacity(self: *Self, key: Key) !void {
//             const index = keyToIndex(key);
// 
//             if (index < self.sparse.len) return;
// 
//             const old_len = self.sparse.len;
//             const new_len = index + 1;
// 
//             self.sparse = try self.allocator.realloc(self.sparse, new_len);
//             @memset(self.sparse[old_len..], INVALID);
//         }
// 
//         pub fn has(self: *Self, key: Key) bool {
//             const index = keyToIndex(key);
// 
//             if (index >= self.sparse.len) return false;
// 
//             const dense_idx = self.sparse[index];
//             if (dense_idx == INVALID) return false;
// 
//             return self.dense_keys.items[dense_idx] == key;
//         }
// 
//         pub fn get(self: *Self, key: Key) ?*T {
//             if (!self.has(key)) return null;
//             return &self.dense.items[self.sparse[keyToIndex(key)]];
//         }
// 
//         pub fn insert(self: *Self, key: Key, value: T) !void {
//             try self.ensureCapacity(key);
// 
//             const index = keyToIndex(key);
// 
//             if (self.has(key)) {
//                 self.dense.items[self.sparse[index]] = value;
//                 return;
//             }
// 
//             const dense_idx = self.dense.items.len;
// 
//             try self.dense.append(value);
//             try self.dense_keys.append(key);
// 
//             self.sparse[index] = dense_idx;
//         }
// 
//         pub fn remove(self: *Self, key: Key) void {
//             if (!self.has(key)) return;
// 
//             const index = keyToIndex(key);
//             const dense_idx = self.sparse[index];
//             const last_idx = self.dense.items.len - 1;
// 
//             // swap-remove
//             self.dense.items[dense_idx] = self.dense.items[last_idx];
//             self.dense_keys.items[dense_idx] = self.dense_keys.items[last_idx];
// 
//             const moved_key = self.dense_keys.items[dense_idx];
//             self.sparse[keyToIndex(moved_key)] = dense_idx;
// 
//             _ = self.dense.pop();
//             _ = self.dense_keys.pop();
// 
//             self.sparse[index] = INVALID;
//         }
//     };
// }
