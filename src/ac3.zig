const std = @import("std");
const math = std.math;
const testing = std.testing;
const queue = @import("./queue.zig");

////////
// Types

/// Variable's domain of values
pub const Domain = []const i32;

/// Constraint variable
pub const Variable = struct {
    /// Variable name
    name: []const u8,
    /// Domain of value
    domain: Domain,
    /// Parallel to .domain, flag marks if each value of .domain is valid
    domainValid: []bool,
    /// INTERNAL: Iterator index
    _index: usize = 0,

    /// Create a variable
    pub fn init(allocator: std.mem.Allocator, data: struct { name: []const u8, domain: Domain }) !Variable {
        var domainValid: []bool = try allocator.alloc(bool, data.domain.len);
        for (0..data.domain.len) |i| {
            domainValid[i] = true;
        }

        return Variable{
            .name = data.name,
            .domain = data.domain,
            .domainValid = domainValid,
        };
    }

    /// Provide an array of only valid domain values
    pub fn getDomainValues(self: Variable, allocator: std.mem.Allocator) ![]const i32 {
        // Determine number of valid valude
        var len: usize = 0;
        for (self.domainValid) |dv| {
            if (dv) {
                len += 1;
            }
        }

        // Populate new array with only valid domain values
        var compressedDomain = try allocator.alloc(i32, len);

        var j: usize = 0;
        for (0.., self.domainValid) |i, dv| {
            if (dv) {
                compressedDomain[j] = self.domain[i];
                j += 1;
            }
        }

        return compressedDomain;
    }

    /// Create/Init iterator
    pub fn iterator(self: *Variable) *Variable {
        self._index = 0;
        return self;
    }

    /// Get next iterator value
    pub fn next(self: *Variable) ?i32 {
        const index = self._index;
        for (self.domain[index..], self.domainValid[index..]) |d, dv| {
            self._index += 1;
            if (dv) {
                return d;
            }
        }
        return null;
    }
};

/// All variables to process
pub const Variables = std.StringHashMap(Variable);

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
    UndefinedVariable,
};

////////////
// Functions

/// Process unary constraint for variable
/// Reduce variable's domain as appropriate
pub fn processUnaryConstraint(variable: Variable, constraint: UnaryConstraint) void {
    // Iterate through all values in the domain
    for (0.., variable.domain, variable.domainValid) |i, d, dv| {
        if (dv) {
            const pass = constraint.constraint(d);
            if (!pass) {
                //std.debug.print("d: {} (i={}) FAILED f: {}\n", .{ d, i, constraint });
                // value failed constraint, remove from valid values
                variable.domainValid[i] = false;
            }
        } else {
            //std.debug.print("skipping {} {}\n", .{ dv, d });
        }
    }
}

/// Process all unary constraints
pub fn processUnaryConstraints(variables: Variables, constraints: UnaryConstraints) !void {
    for (constraints) |constraint| {
        if (!variables.contains(constraint.name)) {
            std.debug.print("Error: Variable '{s}' not found\n", .{constraint.name});
            return Ac3Error.UndefinedVariable;
        }

        const variable = variables.get(constraint.name);
        //std.debug.print("c: {any} v: {any}\n", .{ constraint, variable });
        processUnaryConstraint(variable.?, constraint);
    }
}

/// Process binary constraint for variables
/// Reduce variable1's domain as appropriate
/// Returns if variable1's domain changed
pub fn processBinaryConstraint(variable1: Variable, variable2: Variable, constraint: BinaryConstraint) bool {
    var changed = false;
    // Iterate through all values in the domains
    for (0.., variable1.domain, variable1.domainValid) |index1, d1, dv1| {
        if (dv1) {
            var success = true;
            for (0.., variable2.domain, variable2.domainValid) |index2, d2, dv2| {
                if (dv2) {
                    _ = index2;
                    const pass = constraint.constraint(d1, d2);
                    if (!pass) {
                        //std.debug.print("d: {} (i={}) FAILED f: {}\n", .{ d, i, constraint });
                        // value failed constraint, remove from valid values
                        success = false;
                    }
                } else {
                    //std.debug.print("skipping {} {}\n", .{ dv, d });
                }
            }

            if (!success) {
                // no values in variable2 worked for this variable1 value. it fails
                variable1.domainValid[index1] = false;
                changed = true;
            }
        }
    }
    return changed;
}

/// Process all binary constraints
pub fn processBinaryConstraints(allocator: std.mem.Allocator, variables: Variables, constraints: BinaryConstraints) !void {
    // Processing is driven off of a list of variable names to process
    var work_queue = queue.Queue([]const u8).init(allocator);
    defer work_queue.deinit() catch {};

    // Init processing - Add all variables
    var variable_iterator = variables.iterator();
    while (variable_iterator.next()) |x| {
        try work_queue.enqueue(x.value_ptr.name);
    }
    // std.debug.print("queue length: {d}\n", .{work_queue.count()});

    // Process variables until nothing more changes
    while (work_queue.dequeue()) |variable_name| {
        // std.debug.print("process: {}\n", .{constraint});

        // Process all constraints that use this variable
        for (constraints) |constraint| {
            if (!std.mem.eql(u8, constraint.name1, variable_name) and (!std.mem.eql(u8, constraint.name2, variable_name))) {
                // constraint does not use this variable, skip
                continue;
            }

            // Ensure both variables for constraint exist
            if (!variables.contains(constraint.name1)) {
                std.debug.print("Error: Variable '{s}' not found\n", .{constraint.name1});
                return Ac3Error.UndefinedVariable;
            } else if (!variables.contains(constraint.name2)) {
                std.debug.print("Error: Variable '{s}' not found\n", .{constraint.name2});
                return Ac3Error.UndefinedVariable;
            }

            const variable1 = variables.get(constraint.name1);
            const variable2 = variables.get(constraint.name2);
            //std.debug.print("c: {any} v1: {any} v2: {any}\n", .{ constraint, variable1, variable2 });
            const changed = processBinaryConstraint(variable1.?, variable2.?, constraint);

            if (changed) {
                // variable1 domain changed, all all impacted constraints to processing queue

                // Add neighbors of changed variable (neighbor = share a constraint)
                // std.debug.print("changed\n", .{});
                for (constraints) |c| {
                    if (std.mem.eql(u8, c.name1, variable_name)) {
                        try work_queue.enqueue(c.name2);
                    } else if (std.mem.eql(u8, c.name2, variable_name)) {
                        try work_queue.enqueue(c.name1);
                    }
                }
                // std.debug.print("queue length: {d}\n", .{work_queue.count()});
            }
        }
    }
}

/// Solve using AC-3 algorithm
pub fn solve(allocator: std.mem.Allocator, variables: Variables, unary_constraints: UnaryConstraints, binary_constraints: BinaryConstraints) !void {
    const foo = try allocator.alloc(i32, 10);
    defer allocator.free(foo);

    try processUnaryConstraints(variables, unary_constraints);
    try processBinaryConstraints(allocator, variables, binary_constraints);
}

////////
// Tests

test "todo" {
    const allocator = std.testing.allocator;
    const v = try Variable.init(allocator, .{ .name = "foo", .domain = &[_]i32{ 11, 22, 33 } });

    try testing.expect(std.mem.eql(u8, v.name, "foo"));
    try testing.expect(v.domain.len == 3);
    try testing.expect(v.domain[1] == 22);
    try testing.expect(1 == 1);
}
