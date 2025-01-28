const std = @import("std");

// Queue of type T
pub fn Queue(comptime T: type) type {
    return struct {
        /// Queue object
        const This = @This();
        /// Queue is stored as a linked list, this is a node
        const Node = struct {
            data: T,
            next: ?*Node,
        };

        /// Allocator
        _allocator: std.mem.Allocator,
        /// Start of queue
        _start: ?*Node,
        /// End of queue
        _end: ?*Node,
        /// Length of queue
        _count: usize = 0,

        /// Create queue
        pub fn init(allocator: std.mem.Allocator) This {
            return This{
                ._allocator = allocator,
                ._start = null,
                ._end = null,
            };
        }

        /// Queue cleanup
        pub fn deinit(self: *This) !void {
            // deallocate all queue fiels
            while (self.dequeue()) |_| {}
        }

        /// Add item to queue
        pub fn enqueue(self: *This, value: T) !void {
            const node = try self._allocator.create(Node);
            node.* = .{ .data = value, .next = null };
            if (self._end) |end| {
                self._count += 1;
                end.next = node;
            } else {
                self._count += 1;
                self._start = node;
            }
            self._end = node;
        }

        /// Remove item to queue
        pub fn dequeue(self: *This) ?T {
            const start = self._start orelse return null;
            defer self._allocator.destroy(start);
            if (start.next) |next| {
                self._count -= 1;
                self._start = next;
            } else {
                self._count -= 1;
                self._start = null;
                self._end = null;
            }
            return start.data;
        }

        /// Number of items in queue
        pub fn count(self: *This) usize {
            return self._count;
        }
    };
}
