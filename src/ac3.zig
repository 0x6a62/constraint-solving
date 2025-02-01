const std = @import("std");
const math = std.math;
const testing = std.testing;
const queue = @import("./queue.zig");

////////
// Types

/// Variable's domain of values
pub const Domain = []i32;

/// Constraint variable
pub const Variable = struct {
    /// Variable name
    name: []const u8,
    /// INTERNAL: Domain of value
    _domain: Domain,
    /// INTERNAL: domain length
    _length: usize = 0,

    /// Create a variable
    pub fn init(data: struct { name: []const u8, domain: Domain }) !Variable {
        return Variable{
            .name = data.name,
            ._domain = data.domain,
            ._length = data.domain.len,
        };
    }

    /// Domain values
    pub fn domain(self: *const Variable) []i32 {
        return self._domain[0..self._length];
    }

    /// Length of domain array
    pub fn length(self: *const Variable) usize {
        return self._length;
    }

    /// Remove value by index from the domain
    pub fn removeDomainIndex(self: *Variable, index: usize) !void {
        if (index >= self._length) {
            return Ac3Error.InvalidIndex;
        }

        // Shift everything left and reduce length by one
        for (index..(self._length - 1)) |i| {
            self._domain[i] = self._domain[i + 1];
        }

        self._length -= 1;
    }
};

/// All variables to process
const Variables = []Variable;

/// Unary constraint
pub const UnaryConstraint = struct { name: []const u8, constraint: *const (fn (i32) bool) };

/// All unary constraints
pub const UnaryConstraints = []const UnaryConstraint;

/// Binary constraint
pub const BinaryConstraint = struct { name1: []const u8, name2: []const u8, constraint: *const (fn (i32, i32) bool) };

/// All binary constraints
pub const BinaryConstraints = []const BinaryConstraint;

/// AC3 Errors
pub const Ac3Error = error{
    /// Invalid index reference in domain array
    InvalidIndex,
    /// Failure to remove a value from the domain
    RemoveDomainIndex,
    /// Specified variable is not defined in the variables array
    UndefinedVariable,
};

////////////
// Functions

/// Does variable list contain a specific variable
pub fn variablesContain(variables: Variables, name: []const u8) bool {
    for (variables) |v| {
        if (std.mem.eql(u8, v.name, name)) {
            return true;
        }
    }
    return false;
}

/// Get the index of a variable in the variable list
pub fn variablesIndexOf(variables: Variables, name: []const u8) !usize {
    for (0.., variables) |i, v| {
        if (std.mem.eql(u8, v.name, name)) {
            return i;
        }
    }
    return Ac3Error.UndefinedVariable;
}

/// Process unary constraint for variable
/// Reduce variable's domain as appropriate
pub fn processUnaryConstraint(variable: *Variable, constraint: UnaryConstraint) !void {
    // Iterate through all values in the domain
    // Process domain in reverse, so if I need to remove an item, it
    // doesn't shift the array out from underneath me
    // Can't do length->0, because continue block takes usize to -1 (error)

    if (variable.length() == 0) {
        // Already empty, nothing to process
        return;
    }

    const max = variable.length() - 1;
    var _i: usize = 0;
    while (_i <= max) : (_i += 1) {
        const irev = max - _i;
        const d = variable.domain()[irev];

        const pass = constraint.constraint(d);
        if (!pass) {
            // value failed constraint, remove from valid values
            variable.removeDomainIndex(irev) catch {
                return Ac3Error.RemoveDomainIndex;
            };
        }
    }
}

/// Process all unary constraints
/// Reduce variable's domain as appropriate
pub fn processUnaryConstraints(variables: Variables, constraints: UnaryConstraints) !void {
    for (constraints) |constraint| {
        if (!variablesContain(variables, constraint.name)) {
            return Ac3Error.UndefinedVariable;
        }

        const vi = try variablesIndexOf(variables, constraint.name);
        try processUnaryConstraint(&(variables[vi]), constraint);
    }
}

/// Process binary constraint for variables
/// Reduce variable1's domain as appropriate
/// Returns if variable1's domain changed
pub fn processBinaryConstraint(variable1: *Variable, variable2: *Variable, constraint: BinaryConstraint) !bool {
    var changed = false;
    // Iterate through all values in the domains
    // Process domain in reverse, so if I need to remove an item, it
    // doesn't shift the array out from underneath me
    // Can't do length->0, because continue block takes usize to -1 (error)

    if (variable1.length() == 0) {
        // Already empty, nothing to process
        return false;
    }

    const max1 = variable1.length() - 1;
    var _index1: usize = 0;
    while (_index1 <= max1) : (_index1 += 1) {
        const index1rev = max1 - _index1;
        const d1 = variable1._domain[index1rev];

        var success = false;
        for (variable2.domain()) |d2| {
            const pass = constraint.constraint(d1, d2);
            if (pass) {
                // value failed constraint, remove from valid values
                success = true;
                // No need to process anymore v2s, already failed
                break;
            }
        }

        if (!success) {
            // no values in variable2 worked for this variable1 value. it fails
            variable1.removeDomainIndex(index1rev) catch |e| {
                std.debug.print("Error: Binary Remove Domain Value {any} v {any} =>  {any}\n", .{ index1rev, variable1._length, e });
                return Ac3Error.RemoveDomainIndex;
            };
            changed = true;
        }
    }
    return changed;
}

/// Process all binary constraints
pub fn processBinaryConstraints(allocator: std.mem.Allocator, variables: Variables, constraints: BinaryConstraints) !void {
    // Processing is driven off of a list of variable names to process
    var work_queue = queue.Queue([]const u8).init(allocator);
    defer work_queue.deinit() catch {};

    // Init processing - Add all variables to start
    for (variables) |v| {
        try work_queue.enqueue(v.name);
    }

    // Process variables until nothing more changes
    while (work_queue.dequeue()) |variable_name| {
        // Process all constraints that use this variable
        for (constraints) |constraint| {
            if (!std.mem.eql(u8, constraint.name1, variable_name) and (!std.mem.eql(u8, constraint.name2, variable_name))) {
                // constraint does not use this variable, skip
                continue;
            }

            // Ensure both variables for constraint exist
            if (!variablesContain(variables, constraint.name1)) {
                return Ac3Error.UndefinedVariable;
            } else if (!variablesContain(variables, constraint.name2)) {
                return Ac3Error.UndefinedVariable;
            }

            const v1i = try variablesIndexOf(variables, constraint.name1);
            const v2i = try variablesIndexOf(variables, constraint.name2);
            const changed = try processBinaryConstraint(&variables[v1i], &variables[v2i], constraint);

            if (changed) {
                // variable1 domain changed, add neighbors for reprocessing (neighbor = share a constraint)
                for (constraints) |c| {
                    if (std.mem.eql(u8, c.name1, variable_name)) {
                        try work_queue.enqueue(c.name2);
                    } else if (std.mem.eql(u8, c.name2, variable_name)) {
                        try work_queue.enqueue(c.name1);
                    }
                }
            }
        }
    }
}

/// Solve constraints using AC-3 algorithm
pub fn solve(allocator: std.mem.Allocator, variables: Variables, unary_constraints: UnaryConstraints, binary_constraints: BinaryConstraints) !bool {
    try processUnaryConstraints(variables, unary_constraints);
    try processBinaryConstraints(allocator, variables, binary_constraints);

    // Determine if it was successful
    // If any variable's domain is empty, its a failure
    for (variables) |v| {
        if (v._length == 0) {
            return false;
        }
    }
    return true;
}

////////
// Tests

test "variable creation" {
    var d = [_]i32{
        11,
        22,
        33,
    };
    const v = try Variable.init(.{ .name = "foo", .domain = &d });

    try testing.expect(std.mem.eql(u8, v.name, "foo"));
    try testing.expect(v._domain.len == 3);
    try testing.expect(v._domain[1] == 22);
}

test "variable - domain" {
    var d = [_]i32{
        11,
        22,
        33,
    };
    const v = try Variable.init(.{ .name = "foo", .domain = &d });

    const values = v.domain();

    try testing.expect(values.len == 3);
    try testing.expect(values[0] == 11);
    try testing.expect(values[1] == 22);
    try testing.expect(values[2] == 33);
}

fn isEven(x: i32) bool {
    return @mod(x, 2) == 0;
}

test "unary constraint" {
    var d = [_]i32{
        11,
        22,
        33,
        100,
        200,
        300,
        400,
        501,
    };
    var v = try Variable.init(.{ .name = "foo", .domain = &d });

    try processUnaryConstraint(
        &v,
        UnaryConstraint{ .name = "foo", .constraint = &isEven },
    );

    try testing.expect(std.mem.eql(i32, v.domain(), &[_]i32{
        22,
        100,
        200,
        300,
        400,
    }));
}

fn isLessThan(x: i32, y: i32) bool {
    return x < y;
}

test "binary constraint" {
    var d1 = [_]i32{
        11,
        22,
        33,
        100,
        200,
        300,
        400,
        501,
    };
    var v1 = try Variable.init(.{ .name = "v1", .domain = &d1 });
    var d2 = [_]i32{
        11,
        22,
        33,
        100,
    };
    var v2 = try Variable.init(.{ .name = "v2", .domain = &d2 });

    const changed = try processBinaryConstraint(
        &v1,
        &v2,
        BinaryConstraint{ .name1 = "v1", .name2 = "v2", .constraint = &isLessThan },
    );

    try testing.expect(changed == true);
    try testing.expect(std.mem.eql(i32, v1.domain(), &[_]i32{
        11,
        22,
        33,
    }));
}
