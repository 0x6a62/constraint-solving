const std = @import("std");
const ac3 = @import("ac3");

//////////////
// Constraints

fn isEven(x: i32) bool {
    return @mod(x, 2) == 0;
}

fn isOdd(x: i32) bool {
    return !(isEven(x));
}

fn isPowerOfTwo(x: i32) bool {
    return std.math.isPowerOfTwo(x);
}

fn isLessThan(x: i32, y: i32) bool {
    return x < y;
}

fn isSumEven(x: i32, y: i32) bool {
    return @rem(x + y, 2) == 0;
}

//////////
// Helpers

fn rangeToArray(allocator: std.mem.Allocator, start: usize, end: usize) ![]i32 {
    var a: []i32 = try allocator.alloc(i32, end - start);
    for (0.., start..end) |i, x| {
        a[i] = @intCast(x);
    }

    return a;
}

/// main
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const stdout = std.io.getStdOut().writer();

    // new
    {
        var d1 = [_]i32{
            1,
            2,
            3,
            4,
            5,
            6,
            7,
            8,
        };
        const v1 = try ac3.Variable.init(.{ .name = "abc", .domain = &d1 });

        var d2 = [_]i32{
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
            11,
            12,
            13,
            14,
            15,
            16,
            17,
            18,
        };
        const v2 = try ac3.Variable.init(.{ .name = "def", .domain = &d2 });
        var d3 = [_]i32{
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
            11,
            12,
            13,
            14,
            15,
            16,
            17,
            18,
        };
        const v3 = try ac3.Variable.init(.{ .name = "ghi", .domain = &d3 });

        const d4 = try rangeToArray(allocator, 10, 20);
        defer allocator.free(d4);
        std.debug.print("{any}\n", .{d4});
        const v4 = try ac3.Variable.init(.{ .name = "jkl", .domain = d4 });

        const d5 = try rangeToArray(allocator, 1, 30);
        defer allocator.free(d5);
        std.debug.print("{any}\n", .{d5});
        const v5 = try ac3.Variable.init(.{ .name = "mno", .domain = d5 });

        var variables = [_]ac3.Variable{ v1, v2, v3, v4, v5 };
        std.debug.print("variables: {d}\n", .{variables.len});

        const unary_constraints = [_]ac3.UnaryConstraint{
            ac3.UnaryConstraint{ .name = "abc", .constraint = &isEven },
            ac3.UnaryConstraint{ .name = "def", .constraint = &isOdd },
            ac3.UnaryConstraint{ .name = "ghi", .constraint = &isPowerOfTwo },
            ac3.UnaryConstraint{ .name = "jkl", .constraint = &isOdd },
        };

        const binary_constraints = [_]ac3.BinaryConstraint{
            ac3.BinaryConstraint{ .name1 = "abc", .name2 = "def", .constraint = &isLessThan },
            ac3.BinaryConstraint{ .name1 = "def", .name2 = "jkl", .constraint = &isSumEven },
            ac3.BinaryConstraint{ .name1 = "jkl", .name2 = "def", .constraint = &isSumEven },
            ac3.BinaryConstraint{ .name1 = "abc", .name2 = "jkl", .constraint = &isLessThan },
            ac3.BinaryConstraint{ .name1 = "mno", .name2 = "jkl", .constraint = &isLessThan },
        };

        const success = try ac3.solve(allocator, &variables, &unary_constraints, &binary_constraints);

        // show results
        std.debug.print("success: {}\n", .{success});
        for (variables) |v| {
            const d = v.domain();
            // defer allocator.free(d);
            std.debug.print("{s} = {d}\n", .{ v.name, d });
        }
    }

    try stdout.print("done\n", .{});
}
