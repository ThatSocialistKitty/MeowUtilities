const std: type = @import("std");
const fileSystem: type = @import("fileSystem.zig");
const zlib: type = @cImport({
    @cInclude("zlib-ng.h");
});

pub fn EventBus(comptime EventUnion: type) type {
    std.debug.assert(std.meta.activeTag(@typeInfo(EventUnion)) == .@"union");
    
    return struct {
        pub const Event: type = struct {
            preventDefault: bool = false,
            data: EventUnion
        };
        
        const ConsumerImplementation: type = struct {
            id: usize,
            pollingIndex: usize,
            eventBus: *EventBus(EventUnion)
        };
        
        pub const Consumer: type = opaque {
            pub fn destroy(self: *@This()) void {
                const consumer: *ConsumerImplementation = @ptrCast(@alignCast(self));
                consumer.eventBus.destroyConsumer(consumer);
            }
            
            pub fn poll(self: *@This()) ?*Event {
                const consumer: *ConsumerImplementation = @ptrCast(@alignCast(self));
                return consumer.eventBus.pollConsumer(consumer);
            }
        };
        
        const Implementation: type = struct {
            allocator: std.mem.Allocator,
            events: std.ArrayList(Event),
            consumers: std.ArrayList(*ConsumerImplementation),
            nextConsumerId: usize
        };
        
        pub fn create(allocator: std.mem.Allocator) *@This() {
            const eventBus: *Implementation = allocator.create(Implementation) catch unreachable;
            
            eventBus.allocator = allocator;
            eventBus.events = .empty;
            eventBus.consumers = .empty;
            eventBus.nextConsumerId = 0;
            
            return @ptrCast(eventBus);
        }
        
        pub fn destroy(self: *@This()) void {
            const eventBus: *Implementation = @ptrCast(@alignCast(self));
            
            eventBus.events.deinit(eventBus.allocator);
            
            while (eventBus.consumers.items.len > 0) {
                self.destroyConsumer(eventBus.consumers.items[0]);
            }
            
            eventBus.consumers.deinit(eventBus.allocator);
            
            eventBus.allocator.destroy(eventBus);
        }
        
        pub fn createConsumer(self: *@This()) *Consumer { 
            const eventBus: *Implementation = @ptrCast(@alignCast(self));
            
            const consumer: *ConsumerImplementation = eventBus.allocator.create(ConsumerImplementation) catch unreachable;
            
            consumer.id = eventBus.nextConsumerId;
            consumer.pollingIndex = 0;
            consumer.eventBus = self;
            
            eventBus.nextConsumerId += 1;
            
            eventBus.consumers.append(eventBus.allocator,consumer) catch unreachable;
            
            return @ptrCast(consumer);
        }
        
        fn pollConsumer(self: *@This(),consumer: *ConsumerImplementation) ?*Event {
            const eventBus: *Implementation = @ptrCast(@alignCast(self));
            
            var smallestPollingIndex: usize = std.math.maxInt(usize);
            
            for (eventBus.consumers.items) |otherConsumerLol| {
                if (otherConsumerLol.pollingIndex < smallestPollingIndex) {
                    smallestPollingIndex = otherConsumerLol.pollingIndex;
                }
            }
            
            if (smallestPollingIndex > 1) {
                const removeCount: usize = smallestPollingIndex - 1;
                
                var index: usize = 0;
                
                while (index < removeCount and eventBus.events.items.len > 0) : (index += 1) {
                    _ = eventBus.events.orderedRemove(0);
                }
                
                for (eventBus.consumers.items) |otherConsumerLol| {
                    otherConsumerLol.pollingIndex -= removeCount;
                }
            }
            
            const event: ?*Event = if (consumer.pollingIndex < eventBus.events.items.len) &eventBus.events.items[consumer.pollingIndex] else null;
            
            if (event != null) {
                consumer.pollingIndex += 1;
            }
            
            return event;
        }
        
        fn destroyConsumer(self: *@This(),consumer: *ConsumerImplementation) void {
            const eventBus: *Implementation = @ptrCast(@alignCast(self));
            
            for (eventBus.consumers.items,0..) |otherConsumerLol,index| {
                if (otherConsumerLol == consumer) {
                    eventBus.allocator.destroy(eventBus.consumers.orderedRemove(index));
                    break;
                }
            }
        }
        
        pub fn append(self: *@This(),event: Event) void {
            const eventBus: *Implementation = @ptrCast(@alignCast(self));
            eventBus.events.append(eventBus.allocator,event) catch unreachable;
        }
    };
}

pub const Image: type = opaque {
    const Format: type = enum {
        Png
    };
    
    const formatSignatures: []const []const u8 = &.{
        &.{0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a}
    };
    
    const Metadata: type = struct {
        format: Format,
        dimensions: [2]u32,
        resolution: u32,
        size: usize,
        tags: ?[]const []const u8 = null
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
    
    fn decodePng(allocator: std.mem.Allocator,imageContents: []const u8,output: struct {pixels: *[]Pixel,metadata: *Metadata}) !void {
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
        
        {
            var byteIndex: usize = 8;
            const fieldSize: usize = 4;
            
            while (true) {
                var chunk = std.mem.zeroes(Chunk);
                
                chunk.dataLength = std.mem.readPackedInt(u32,imageContents[byteIndex..byteIndex + fieldSize],0,.big);
                
                byteIndex += fieldSize;
                
                const typeField: []const u8 = imageContents[byteIndex..byteIndex + fieldSize];
                
                var chunkIsRelevant: bool = false;
                
                inline for (@typeInfo(ChunkKind).@"enum".fields,0..) |field,fieldIndex| {
                    if (std.mem.eql(u8,imageContents[byteIndex..byteIndex + fieldSize],field.name)) {
                        chunk.kind = @enumFromInt(fieldIndex);
                        chunkIsRelevant = true;
                        break;
                    }
                }
                
                byteIndex += fieldSize;
                
                const dataField: []const u8 = imageContents[byteIndex..byteIndex + chunk.dataLength];
                
                chunk.data = imageContents[byteIndex..byteIndex + chunk.dataLength];
                
                byteIndex += chunk.dataLength;
                
                chunk.checksum = std.mem.readPackedInt(u32,imageContents[byteIndex..byteIndex + fieldSize],0,.big);
                
                byteIndex += fieldSize;
                
                if (chunkIsRelevant) {
                    {
                        var hash: std.hash.Crc32 = .init();
                        
                        hash.update(typeField);
                        hash.update(dataField);
                        
                        if (hash.final() != chunk.checksum) return error.CorruptChunkFound;
                    }
                    
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
                            pixelSize = channelCount * (bitDepth / 8);
                            
                            output.metadata.size = bitDepth * channelCount * output.metadata.resolution / 8;
                        },
                        .IDAT => compressedScanlines.appendSlice(allocator,chunk.data) catch unreachable,
                        .tEXt => tags.append(allocator,allocator.dupe(u8,chunk.data) catch unreachable) catch unreachable,
                        .IEND => break
                    }
                }
            }
        }
        
        output.metadata.tags = tags.toOwnedSlice(allocator) catch unreachable;
        
        const scanlines: []u8 = allocator.alloc(u8,((output.metadata.dimensions[0] * channelCount * bitDepth + 7) / 8 + 1) * output.metadata.dimensions[1]) catch unreachable;
        defer allocator.free(scanlines);
        
        var bytesWritten = scanlines.len;
        
        if (zlib.zng_uncompress(scanlines.ptr,&bytesWritten,compressedScanlines.items.ptr,compressedScanlines.items.len) != zlib.Z_OK) return error.DecompressionFailure;
        
        output.pixels.* = allocator.alloc(Pixel,output.metadata.dimensions[0] * output.metadata.dimensions[1]) catch unreachable;
        
        const FilterKind: type = enum {
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
            const filterType: FilterKind = @enumFromInt(scanlines[rowStartIndex]);
            const scanline: []u8 = scanlines[rowStartIndex + 1..rowStartIndex + 1 + scanlineDataLength];
            
            switch (filterType) {
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
    
    pub fn create(allocator: std.mem.Allocator,imageContents: []const u8) !*@This() {
        const image: *Implementation = allocator.create(Implementation) catch unreachable;
        
        image.allocator = allocator;
        
        {
            var formatAssigned: bool = false;
            
            inline for (formatSignatures,0..) |signature,signatureIndex| {
                if (std.mem.startsWith(u8,imageContents,signature)) {
                    image.metadata.format = @enumFromInt(@typeInfo(Format).@"enum".fields[signatureIndex].value);
                    formatAssigned = true;
                    break;
                }
            }
            
            if (!formatAssigned) {
                return error.UnsupportedFormat;
            }
        }
        
        switch (image.metadata.format) {
            .Png => try decodePng(allocator,imageContents,.{
                .pixels = &image.pixels,
                .metadata = &image.metadata
            })
        }
        
        return @ptrCast(image);
    }
    
    pub fn createFromFile(allocator: std.mem.Allocator,path: []const u8) !*@This() {
        const imageContents: []u8 = getValue: {
            const selfDirectory: std.fs.Dir = try fileSystem.openSelfDirectory(.{});
            const file: std.fs.File = try selfDirectory.openFile(path,.{
                .mode = .read_only
            });
            
            const fileStat: std.fs.File.Stat = try file.stat();
            
            var fileReaderBuffer: [256]u8 = undefined;
            break :getValue try std.Io.Reader.readAlloc(@constCast(&file.reader(&fileReaderBuffer).interface),allocator,fileStat.size);
        };
        defer allocator.free(imageContents);
        
        return create(allocator,imageContents);
    }
    
    pub fn destroy(self: *@This()) void {
        const image: *Implementation = @ptrCast(@alignCast(self));
        
        image.allocator.free(image.pixels);
        
        for (image.metadata.tags) |tag| {
            image.allocator.free(tag);
        }
        
        image.allocator.free(image.metadata.tags);
        
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
