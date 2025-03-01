/// Common functions
const std = @import("std");

/// Create an array using a range, with a step value
/// The range is inclusive of start & end (this varies from Zig's range)
pub fn stepRangeToArray(comptime T: type, allocator: std.mem.Allocator, start: T, end: T, step: T) ![]T {
    var len: usize = @intCast(@divTrunc(end - start + 1, step));
    if (@mod(end - start + 1, step) != 0) {
        len += 1;
    }

    const a: []T = try allocator.alloc(T, len);
    var v = start;
    for (0..len) |i| {
        a[i] = @as(T, v);
        v += step;
    }
    return a;
}

/// Create an array using a range
/// The range is inclusive of start & end (this varies from Zig's range)
pub fn rangeToArray(comptime T: type, allocator: std.mem.Allocator, start: T, end: T) ![]T {
    const len: usize = @intCast(end - start + 1);
    const a: []T = try allocator.alloc(T, len);
    var v = start;
    for (0..len) |i| {
        a[i] = @as(T, v);
        v += 1;
    }
    return a;
}

/// Index value of first instance of value (or null if not found)
pub fn indexOf(comptime T: type, list: []const T, v: T) ?usize {
    for (0.., list) |i, x| {
        switch (T) {
            i32 => {
                if (x == v) {
                    return i;
                }
            },
            []const u8 => {
                if (std.mem.eql(u8, x, v)) {
                    return i;
                }
            },
            else => {
                // @compileError("unsupported type");
                if (x == v) {
                    return i;
                }
            },
        }
    }
    return null;
}

/// Does the array contain a specific value
pub fn contains(comptime T: type, list: []const T, v: T) bool {
    if (indexOf(T, list, v)) |_| {
        return true;
    } else {
        return false;
    }
}

////////
// Tests

test "rangeToArray" {
    const allocator = std.testing.allocator;

    const array_i64 = try rangeToArray(i64, allocator, 1, 10);
    defer allocator.free(array_i64);

    try std.testing.expect(std.mem.eql(i64, array_i64, &[_]i64{
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
    }));

    const array_u8 = try rangeToArray(u8, allocator, 'a', 'f');
    defer allocator.free(array_u8);

    try std.testing.expect(std.mem.eql(u8, array_u8, &[_]u8{
        'a',
        'b',
        'c',
        'd',
        'e',
        'f',
    }));
}

test "stepRangeToArray" {
    const allocator = std.testing.allocator;

    const array_i64_2 = try stepRangeToArray(i64, allocator, 1, 10, 2);
    defer allocator.free(array_i64_2);

    try std.testing.expect(std.mem.eql(i64, array_i64_2, &[_]i64{
        1,
        3,
        5,
        7,
        9,
    }));

    const array_i64_3 = try stepRangeToArray(i64, allocator, 1, 10, 3);
    defer allocator.free(array_i64_3);

    try std.testing.expect(std.mem.eql(i64, array_i64_3, &[_]i64{
        1,
        4,
        7,
        10,
    }));

    const array_u8_2 = try stepRangeToArray(u8, allocator, 'a', 'f', 2);
    defer allocator.free(array_u8_2);

    try std.testing.expect(std.mem.eql(u8, array_u8_2, &[_]u8{
        'a',
        'c',
        'e',
    }));
}

test "indexOf - i32 - found" {
    const a = [_]i32{ 11, 22, 33, 44 };
    const result = indexOf(i32, &a, 22);
    try std.testing.expect(1 == result);
}

test "indexOf - f64 - found" {
    const a = [_]f64{ 11, 22, 33, 44 };
    const result = indexOf(f64, &a, 11);
    try std.testing.expect(0 == result);
}

test "indexOf - bool - found" {
    const a = [_]bool{ false, true, true, true };
    const result = indexOf(bool, &a, false);
    try std.testing.expect(0 == result);
}

test "indexOf - string found" {
    const a = [_][]const u8{ "one", "two", "three" };
    const result = indexOf([]const u8, &a, "three");
    try std.testing.expect(2 == result);
}

test "indexOf - i32 - not found" {
    const a = [_]i32{ 11, 22, 33, 44 };
    const result = indexOf(i32, &a, 999);
    try std.testing.expect(null == result);
}

test "indexOf - f64 - not found" {
    const a = [_]f64{ 11, 22, 33, 44 };
    const result = indexOf(f64, &a, 999);
    try std.testing.expect(null == result);
}

test "indexOf - bool - not found" {
    const a = [_]bool{ true, true, true, true };
    const result = indexOf(bool, &a, false);
    try std.testing.expect(null == result);
}

test "indexOf - string not found" {
    const a = [_][]const u8{ "one", "two", "three" };
    const result = indexOf([]const u8, &a, "nine");
    try std.testing.expect(null == result);
}

test "contains - i32 - found" {
    const a = [_]i32{ 11, 22, 33, 44 };
    const result = contains(i32, &a, 22);
    try std.testing.expect(true == result);
}

test "contains - f64 - found" {
    const a = [_]f64{ 11, 22, 33, 44 };
    const result = contains(f64, &a, 11);
    try std.testing.expect(true == result);
}

test "contains - bool - found" {
    const a = [_]bool{ false, true, false };
    const result = contains(bool, &a, true);
    try std.testing.expect(true == result);
}

test "contains - string found" {
    const a = [_][]const u8{ "one", "two", "three" };
    const result = contains([]const u8, &a, "three");
    try std.testing.expect(true == result);
}

test "contains - i32 - not found" {
    const a = [_]i32{ 11, 22, 33, 44 };
    const result = contains(i32, &a, 999);
    try std.testing.expect(false == result);
}

test "contains - f64 - not found" {
    const a = [_]f64{ 11, 22, 33, 44 };
    const result = contains(f64, &a, 999);
    try std.testing.expect(false == result);
}

test "contains - bool - not found" {
    const a = [_]bool{ false, false, false };
    const result = contains(bool, &a, true);
    try std.testing.expect(false == result);
}

test "contains - string not found" {
    const a = [_][]const u8{ "one", "two", "three" };
    const result = contains([]const u8, &a, "nine");
    try std.testing.expect(false == result);
}
