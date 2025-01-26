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

/// main
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const stdout = std.io.getStdOut().writer();

    // new
    {
        const v1 = try ac3.Variable.init(allocator, .{ .name = "abc", .domain = &[_]i32{ 1, 2, 3, 4, 5, 6, 7, 8 } });
        const v2 = try ac3.Variable.init(allocator, .{ .name = "def", .domain = &[_]i32{ 11, 12, 13, 14, 15, 16, 17, 18 } });
        const v3 = try ac3.Variable.init(allocator, .{ .name = "ghi", .domain = &[_]i32{ 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35 } });

        std.debug.print("v1: {any}\n", .{v1});
        std.debug.print("v2: {any}\n", .{v2});
        std.debug.print("v3: {any}\n", .{v3});

        var variables: ac3.Variables = std.StringHashMap(ac3.Variable).init(allocator);
        defer variables.deinit();

        try variables.put(v1.name, v1);
        try variables.put(v2.name, v2);
        try variables.put(v3.name, v3);

        std.debug.print("variables: {d}\n", .{variables.count()});

        const unary_constraints = [_]ac3.UnaryConstraint{
            ac3.UnaryConstraint{ .name = "abc", .constraint = &isEven },
            ac3.UnaryConstraint{ .name = "abc", .constraint = &isPowerOfTwo },
            ac3.UnaryConstraint{ .name = "def", .constraint = &isOdd },
            ac3.UnaryConstraint{ .name = "ghi", .constraint = &isPowerOfTwo },
        };

        // try ac3.processUnaryConstraints(variables, &unary_constraints);
        try ac3.solve(allocator, variables, &unary_constraints);

        // show variables
        var variables_iterator = variables.iterator();
        while (variables_iterator.next()) |x| {
            // array
            const domainValues = try x.value_ptr.getDomainValues(allocator);
            defer allocator.free(domainValues);
            std.debug.print("array    :: {s} = {any}\n", .{ x.value_ptr.name, domainValues });

            // iterator
            std.debug.print("iterator :: {s} =   ", .{x.value_ptr.name});
            var domain_iterator = x.value_ptr.iterator();
            while (domain_iterator.next()) |dv| {
                std.debug.print("{}, ", .{dv});
            }
            std.debug.print("\n", .{});
        }
    }

    try stdout.print("done\n", .{});
}
