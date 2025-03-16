const std = @import("std");
const bt = @import("back-tracking");
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

fn greaterThan(data: []i32) bool {
    return data[0] > data[1];
}

fn isDouble(data: []i32) bool {
    return data[0] == data[1] * 2;
}

/// main (complex)
pub fn mainComplex() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const ad = try cmn.rangeToArray(i32, allocator, 1, 50);
    defer allocator.free(ad);
    const a = bt.Variable.init(.{ .name = "aa", .domain = ad });

    const bd = try cmn.rangeToArray(i32, allocator, 1, 50);
    defer allocator.free(bd);
    const b = bt.Variable.init(.{ .name = "bb", .domain = bd });

    const cd = try cmn.rangeToArray(i32, allocator, 1, 50);
    defer allocator.free(cd);
    const c = bt.Variable.init(.{ .name = "cc", .domain = cd });

    const dd = try cmn.rangeToArray(i32, allocator, 1, 50);
    defer allocator.free(dd);
    const d = bt.Variable.init(.{ .name = "dd", .domain = dd });

    const ed = try cmn.rangeToArray(i32, allocator, 1, 50);
    defer allocator.free(ed);
    const e = bt.Variable.init(.{ .name = "ee", .domain = ed });

    const fd = try cmn.rangeToArray(i32, allocator, 1, 50);
    defer allocator.free(fd);
    const f = bt.Variable.init(.{ .name = "ff", .domain = fd });

    const gd = try cmn.rangeToArray(i32, allocator, 1, 200);
    defer allocator.free(gd);
    const g = bt.Variable.init(.{ .name = "gg", .domain = gd });

    const hd = try cmn.rangeToArray(i32, allocator, 1, 200);
    defer allocator.free(hd);
    const h = bt.Variable.init(.{ .name = "hh", .domain = hd });

    const id = try cmn.rangeToArray(i32, allocator, 1, 200);
    defer allocator.free(id);
    const i = bt.Variable.init(.{ .name = "ii", .domain = id });

    var variables = [_]bt.Variable{ a, b, c, d, e, f, g, h, i };

    const constraints = [_]bt.NaryConstraint{
        bt.NaryConstraint{ .names = &[_][]const u8{"aa"}, .constraint = &isEven },
        // bt.NaryConstraint{ .names = &[_][]const u8{"bb"}, .constraint = &isEven },
        // bt.NaryConstraint{ .names = &[_][]const u8{"cc"}, .constraint = &isOdd },
        // bt.NaryConstraint{ .names = &[_][]const u8{ "dd", "ee" }, .constraint = &isOdd },
        // bt.NaryConstraint{ .names = &[_][]const u8{ "cc", "ff" }, .constraint = &isSumEven },
        // bt.NaryConstraint{ .names = &[_][]const u8{ "aa", "cc", "ff" }, .constraint = &isLessThan },
        // bt.NaryConstraint{ .names = &[_][]const u8{ "gg", "hh", "ii" }, .constraint = &isRightTriangle },
    };

    const results = try bt.solve(allocator, &variables, &constraints);
    switch (results) {
        bt.SolveResult.values => |x| {
            defer allocator.free(x);
            std.debug.print("Result: success\n", .{});
            for (x) |y| {
                std.debug.print("{s} = {d}\n", .{ y.name, y.value });
            }
        },
        bt.SolveResult.conflicts => |x| {
            defer allocator.free(x);
            std.debug.print("Result: failure\n", .{});
            for (x) |y| {
                std.debug.print("{s} = {d} ({})\n", .{ y.name, y.value, y.conflict });
            }
        },
        bt.SolveResult.exhausted => {
            std.debug.print("Result: failure. No answer found\n", .{});
        },
    }
}

// main (simple)
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.deinit(); // put back in to track leaks/frees
    const allocator = gpa.allocator();

    std.debug.print("\n", .{});

    var ad = [_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    const a = bt.Variable.init(.{ .name = "a", .domain = &ad });
    var bd = [_]i32{ 1, 2, 3, 4, 5 };
    const b = bt.Variable.init(.{ .name = "b", .domain = &bd });

    var variables = [_]bt.Variable{ a, b };
    var constraints = [_]bt.NaryConstraint{ bt.NaryConstraint{ .names = &[_][]const u8{ "a", "b" }, .constraint = &greaterThan }, bt.NaryConstraint{ .names = &[_][]const u8{ "a", "b" }, .constraint = &isDouble } };

    const result = bt.solve(allocator, &variables, &constraints) catch |err| {
        std.debug.print("failure: {any}\n", .{err});
        return;
    };

    switch (result) {
        bt.SolveResult.values => |x| {
            defer allocator.free(result.values);
            std.debug.print("success: {any}\n", .{x});
        },
        bt.SolveResult.conflicts => |x| {
            defer allocator.free(result.conflicts);
            std.debug.print("failure: {any}\n", .{x});
        },
        bt.SolveResult.exhausted => {
            std.debug.print("failure: search exhausted\n", .{});
        },
    }
}
