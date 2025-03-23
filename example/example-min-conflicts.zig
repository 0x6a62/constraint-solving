const std = @import("std");
const mc = @import("min-conflicts");
const cmn = @import("common");

//////////////
// Constraints

fn isEven(values: []i32) bool {
    for (values) |v| {
        if (@mod(v, 2) != 0) {
            return false;
        }
    }
    return true;
}
fn isOdd(values: []i32) bool {
    for (values) |v| {
        if (@mod(v, 2) == 0) {
            return false;
        }
    }
    return true;
}
fn isSumEven(values: []i32) bool {
    var sum: i32 = 0;
    for (values) |v| {
        sum += v;
    }
    return @mod(sum, 2) == 0;
}
fn isLessThan(values: []i32) bool {
    for (values[0 .. values.len - 1], values[1..]) |v1, v2| {
        if (v1 >= v2) {
            return false;
        }
    }
    return true;
}
fn isRightTriangle(values: []i32) bool {
    const a = values[0];
    const b = values[1];
    const c = values[2];
    return a * a + b * b == c * c;
}

/// main
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const ad = try cmn.rangeToArray(i32, allocator, 1, 50);
    defer allocator.free(ad);
    const a = mc.Variable.init(.{ .name = "aa", .domain = ad });

    const bd = try cmn.rangeToArray(i32, allocator, 1, 50);
    defer allocator.free(bd);
    const b = mc.Variable.init(.{ .name = "bb", .domain = bd });

    const cd = try cmn.rangeToArray(i32, allocator, 1, 50);
    defer allocator.free(cd);
    const c = mc.Variable.init(.{ .name = "cc", .domain = cd });

    const dd = try cmn.rangeToArray(i32, allocator, 1, 50);
    defer allocator.free(dd);
    const d = mc.Variable.init(.{ .name = "dd", .domain = dd });

    const ed = try cmn.rangeToArray(i32, allocator, 1, 50);
    defer allocator.free(ed);
    const e = mc.Variable.init(.{ .name = "ee", .domain = ed });

    const fd = try cmn.rangeToArray(i32, allocator, 1, 50);
    defer allocator.free(fd);
    const f = mc.Variable.init(.{ .name = "ff", .domain = fd });

    const gd = try cmn.rangeToArray(i32, allocator, 1, 200);
    defer allocator.free(gd);
    const g = mc.Variable.init(.{ .name = "gg", .domain = gd });

    const hd = try cmn.rangeToArray(i32, allocator, 1, 200);
    defer allocator.free(hd);
    const h = mc.Variable.init(.{ .name = "hh", .domain = hd });

    const id = try cmn.rangeToArray(i32, allocator, 1, 200);
    defer allocator.free(id);
    const i = mc.Variable.init(.{ .name = "ii", .domain = id });

    var variables = [_]mc.Variable{ a, b, c, d, e, f, g, h, i };

    const constraints = [_]mc.NaryConstraint{
        mc.NaryConstraint{ .names = &[_][]const u8{"aa"}, .constraint = &isEven },
        mc.NaryConstraint{ .names = &[_][]const u8{"bb"}, .constraint = &isEven },
        mc.NaryConstraint{ .names = &[_][]const u8{"cc"}, .constraint = &isOdd },
        mc.NaryConstraint{ .names = &[_][]const u8{ "dd", "ee" }, .constraint = &isOdd },
        mc.NaryConstraint{ .names = &[_][]const u8{ "cc", "ff" }, .constraint = &isSumEven },
        mc.NaryConstraint{ .names = &[_][]const u8{ "aa", "cc", "ff" }, .constraint = &isLessThan },
        mc.NaryConstraint{ .names = &[_][]const u8{ "gg", "hh", "ii" }, .constraint = &isRightTriangle },
    };

    const max_rounds = 1000;

    const results = try mc.solve(allocator, max_rounds, &variables, &constraints);
    switch (results) {
        mc.SolveResult.values => |x| {
            defer allocator.free(x);
            std.debug.print("Result: success\n", .{});
            for (x) |y| {
                std.debug.print("{s} = {d}\n", .{ y.name, y.value });
            }
        },
        mc.SolveResult.conflicts => |x| {
            defer allocator.free(x);
            std.debug.print("Result: failure\n", .{});
            for (x) |y| {
                std.debug.print("{s} = {d} ({})\n", .{ y.name, y.value, y.conflict });
            }
        },
    }
}
