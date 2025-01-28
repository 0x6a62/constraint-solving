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
    /// true = ok so far, false = eliminated as possible
    domainValid: []bool,
    /// INTERNAL: Iterator index
    _index: usize = 0,
    /// INTERNAL: Used to allocate domainValid
    _allocator: std.mem.Allocator,

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
            ._allocator = allocator,
        };
    }

    /// Clear memory allocated by creation
    pub fn deinit(self: Variable) void {
        self._allocator.free(self.domainValid);
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
            // Only process variables where "valid" is true
            const pass = constraint.constraint(d);
            if (!pass) {
                // value failed constraint, remove from valid values
                variable.domainValid[i] = false;
            }
        }
    }
}

/// Process all unary constraints
/// Reduce variable's domain as appropriate
pub fn processUnaryConstraints(variables: Variables, constraints: UnaryConstraints) !void {
    for (constraints) |constraint| {
        if (!variables.contains(constraint.name)) {
            std.debug.print("Error: Variable '{s}' not found\n", .{constraint.name});
            return Ac3Error.UndefinedVariable;
        }

        const variable = variables.get(constraint.name);
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
            // Only include currently "valid" domain values (for v1)
            var success = false;
            for (0.., variable2.domain, variable2.domainValid) |index2, d2, dv2| {
                if (dv2) {
                    // Only include current "valid" domain values (for v2)
                    _ = index2;
                    const pass = constraint.constraint(d1, d2);
                    if (pass) {
                        // value failed constraint, remove from valid values
                        success = true;
                        // No need to process anymore v2s, already failed
                        break;
                    }
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

    // Process variables until nothing more changes
    while (work_queue.dequeue()) |variable_name| {
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
            const changed = processBinaryConstraint(variable1.?, variable2.?, constraint);

            if (changed) {
                // variable1 domain changed, all all impacted constraints to processing queue

                // Add neighbors of changed variable (neighbor = share a constraint)
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
pub fn solve(allocator: std.mem.Allocator, variables: Variables, unary_constraints: UnaryConstraints, binary_constraints: BinaryConstraints) !void {
    try processUnaryConstraints(variables, unary_constraints);
    try processBinaryConstraints(allocator, variables, binary_constraints);
}

////////
// Tests

test "variable creation" {
    const allocator = std.testing.allocator;
    const v = try Variable.init(allocator, .{ .name = "foo", .domain = &[_]i32{ 11, 22, 33 } });
    defer v.deinit();

    try testing.expect(std.mem.eql(u8, v.name, "foo"));
    try testing.expect(v.domain.len == 3);
    try testing.expect(v.domain[1] == 22);
}

test "variable - getDomainValues" {
    const allocator = std.testing.allocator;
    const v = try Variable.init(allocator, .{ .name = "foo", .domain = &[_]i32{ 11, 22, 33 } });
    defer v.deinit();

    v.domainValid[1] = false;

    const values = try v.getDomainValues(allocator);
    defer allocator.free(values);

    try testing.expect(values.len == 2);
    try testing.expect(values[0] == 11);
    try testing.expect(values[1] == 33);
}

fn isEven(x: i32) bool {
    return @mod(x, 2) == 0;
}

test "unary constraint" {
    const allocator = std.testing.allocator;
    const v = try Variable.init(allocator, .{ .name = "foo", .domain = &[_]i32{ 11, 22, 33, 100, 200, 300, 400, 501 } });
    defer v.deinit();

    processUnaryConstraint(
        v,
        UnaryConstraint{ .name = "v", .constraint = &isEven },
    );

    // std.debug.print("{any}\n", .{v});
    try testing.expect(std.mem.eql(bool, v.domainValid, &[_]bool{
        false,
        true,
        false,
        true,
        true,
        true,
        true,
        false,
    }));
}

fn isLessThan(x: i32, y: i32) bool {
    return x < y;
}

test "binary constraint" {
    const allocator = std.testing.allocator;
    const v1 = try Variable.init(allocator, .{ .name = "foo", .domain = &[_]i32{ 11, 22, 33, 100, 200, 300, 400, 501 } });
    defer v1.deinit();
    const v2 = try Variable.init(allocator, .{ .name = "foo", .domain = &[_]i32{ 11, 22, 33, 100 } });
    defer v2.deinit();

    const changed = processBinaryConstraint(
        v1,
        v2,
        BinaryConstraint{ .name1 = "v1", .name2 = "v2", .constraint = &isLessThan },
    );

    try testing.expect(changed == true);
    try testing.expect(std.mem.eql(bool, v1.domainValid, &[_]bool{
        true,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
    }));
}
