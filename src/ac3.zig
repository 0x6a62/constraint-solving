const std = @import("std");
const math = std.math;
const testing = std.testing;

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

/// Solve using AC-3 algorithm
pub fn solve(allocator: std.mem.Allocator, variables: Variables, unary_constraints: UnaryConstraints) !void {
    const foo = try allocator.alloc(i32, 10);
    defer allocator.free(foo);
    //std.debug.print("solve: {d}\n", foo.len);

    try processUnaryConstraints(variables, unary_constraints);
}

////////
// Tests

test "todo" {
    // const allocator = std.testing.allocator;
    try testing.expect(1 == 1);
}
