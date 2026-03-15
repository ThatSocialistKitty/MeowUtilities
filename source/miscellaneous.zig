const std: type = @import("std");
const fileSystem: type = @import("fileSystem.zig");

pub fn EventBus(comptime Events: type) type {
    if (std.meta.activeTag(@typeInfo(Events)) != .@"struct") @panic("Events must a struct of functions");
    
    const Event: type = std.meta.DeclEnum(Events);
    const eventCallbacks: []const std.builtin.Type.Declaration = @typeInfo(Events).@"struct".decls;
    
    return opaque {
        const Listener: type = opaque {
            const ListenerImplementation: type = struct {
                allocator: std.mem.Allocator,
                id: usize,
                callback: *const anyopaque,
                eventBus: *EventBus(Events)
            };
            
            fn create(allocator: std.mem.Allocator,id: usize,callback: *const anyopaque,eventBus: *EventBus(Events)) *@This() {
                const listener: *ListenerImplementation = allocator.create(ListenerImplementation) catch unreachable;
                
                listener.allocator = allocator;
                listener.id = id;
                listener.callback = callback;
                listener.eventBus = eventBus;
                
                return @ptrCast(@alignCast(listener));
            }
            
            pub fn destroy(self: *@This()) void {
                const listener: *ListenerImplementation = @ptrCast(@alignCast(self));
                
                unlisten(listener.eventBus,listener.id);
                
                listener.allocator.destroy(listener);
            }
            
            fn getImplementation(self: *@This()) *ListenerImplementation {
                const listener: *ListenerImplementation = @ptrCast(@alignCast(self));
                
                return listener;
            }
        };
        
        const Implementation: type = struct {
            allocator: std.mem.Allocator,
            listeners: [eventCallbacks.len]std.ArrayList(*Listener),
            nextListenerId: usize
        };
        
        pub fn create(allocator: std.mem.Allocator) *@This() {
            const eventBus: *Implementation = allocator.create(Implementation) catch unreachable;
            
            eventBus.allocator = allocator;
            
            inline for (0..eventCallbacks.len) |index| {
                eventBus.listeners[index] = .empty;
            }
            
            eventBus.nextListenerId = 0;
            
            return @ptrCast(eventBus);
        }
        
        pub fn destroy(self: *@This()) void {
            const eventBus: *Implementation = @ptrCast(@alignCast(self));
            
            inline for (0..eventCallbacks.len) |index| {
                const listeners: *std.ArrayList(*Listener) = &eventBus.listeners[index];
                
                for (listeners.items) |listener| {
                    listener.destroy();
                }
                
                listeners.deinit(eventBus.allocator);
            }
            
            eventBus.allocator.destroy(eventBus);
        }
        
        pub fn listen(self: *@This(),event: Event,callback: anytype) *Listener {
            const eventBus: *Implementation = @ptrCast(@alignCast(self));
            const eventEnumIndex: usize = @intFromEnum(event);
            
            const listener: *Listener = .create(eventBus.allocator,eventBus.nextListenerId,@ptrCast(&callback),self);
            
            eventBus.nextListenerId += 1;
            
            eventBus.listeners[eventEnumIndex].append(eventBus.allocator,listener) catch unreachable;
            
            return listener;
        }
        
        fn unlisten(self: *@This(),id: usize) void {
            const eventBus: *Implementation = @ptrCast(@alignCast(self));
            
            inline for (0..eventCallbacks.len) |index| {
                var listeners: *std.ArrayList(*Listener) = &eventBus.listeners[index];
                
                for (listeners.items,0..) |listener,index2| {
                    if (listener.getImplementation().id == id) {
                        _ = listeners.swapRemove(index2);
                        break;
                    }
                }
            }
        }
        
        pub fn emit(self: *@This(),comptime event: Event,arguments: anytype) void {
            const eventBus: *Implementation = @ptrCast(@alignCast(self));
            const eventEnumIndex: usize = @intFromEnum(event);
            
            const defaultCallback = @field(Events,eventCallbacks[eventEnumIndex].name);
            
            const CallbackType = *const @TypeOf(defaultCallback);
            
            const listeners: *std.ArrayList(*Listener) = &eventBus.listeners[eventEnumIndex];
            
            if (listeners.items.len > 0) {
                for (listeners.items) |listener| {
                    @call(.auto,@as(CallbackType,@ptrCast(listener.getImplementation().callback)),arguments);
                }
            } else {
                @call(.auto,@as(CallbackType,@ptrCast(&defaultCallback)),arguments);
            }
        }
    };
}

pub const Image: type = opaque {
    pub const Metadata: type = struct {
        size: [2]usize
    };
    
    const Pixel: type = [4]u8;
    
    const Implementation: type = struct {
        allocator: std.mem.Allocator,
        metadata: Metadata,
        pixels: std.ArrayList(Pixel)
    };
    
    pub const Iterator: type = opaque {
        const IteratorImplementation: type = struct {
            allocator: std.mem.Allocator,
            pixels: []const Pixel
        };
        
        pub fn create(allocator: std.mem.Allocator,pixels: []Pixel) *@This() {
            const iterator: *IteratorImplementation = allocator.create(IteratorImplementation) catch unreachable;
            
            iterator.allocator = allocator;
            iterator.pixels = pixels;
            
            return @ptrCast(iterator);
        }
        
        pub fn destroy(self: *@This()) void {
            const iterator: *IteratorImplementation = @ptrCast(@alignCast(self));
            
            iterator.allocator.destroy(iterator);
        }
        
        pub fn next(self: *@This()) ?Pixel {
            const iterator: *IteratorImplementation = @ptrCast(@alignCast(self));
            
            _ = iterator; return null;
        }
    };
    
    pub fn createFromFile(allocator: std.mem.Allocator,path: []const u8) std.fs.File.OpenError!*@This() {
        const listener: *Implementation = allocator.create(Implementation) catch unreachable;
        
        listener.allocator = allocator;
        
        listener.pixels = .empty;
        
        listener.pixels.appendSlice(listener.allocator,&.{
            .{200,100,255,255},
            .{255,150,255,255}
        }) catch unreachable;
        
        _ = path;
        
        return @ptrCast(listener);
    }
    
    pub fn destroy(self: *@This()) void {
        const image: *Implementation = @ptrCast(@alignCast(self));
        
        image.pixels.deinit(image.allocator);
        image.allocator.destroy(image);
    }
    
    pub fn iterate(self: *@This()) *Iterator {
        const image: *Implementation = @ptrCast(@alignCast(self));
        
        return .create(image.allocator,image.pixels.items);
    }
    
    pub fn getMetadata(self: *@This()) Metadata {
        const image: *Implementation = @ptrCast(@alignCast(self));
        
        return image.metadata;
    }
};
