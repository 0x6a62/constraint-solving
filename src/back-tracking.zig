//! Back-Tracking Constraint Solver
//! Given variables and constraints, attempt to find a solution

const cmn = @import("common");
const std = @import("std");
const testing = std.testing;

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
    /// INTERNAL: rand for shuffling
    _rand: std.Random,

    /// Create a variable
    pub fn init(data: struct { name: []const u8, domain: Domain }) Variable {
        // prng for rand
        const ts: u128 = @bitCast(std.time.nanoTimestamp());
        const seed: u64 = @truncate(ts);
        var prng = std.rand.DefaultPrng.init(seed);

        // Variable
        return Variable{
            .name = data.name,
            ._domain = data.domain,
            ._length = data.domain.len,
            ._rand = prng.random(),
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
            return BackTrackingError.InvalidIndex;
        }

        // Shift everything left and reduce length by one
        for (index..(self._length - 1)) |i| {
            self._domain[i] = self._domain[i + 1];
        }

        self._length -= 1;
    }

    /// Shuffle domain values
    pub fn shuffleDomain(self: *Variable) void {
        std.Random.shuffle(self._rand, i32, self._domain[0..self._length]);
    }

    /// Sort domain values (asc)
    pub fn sortDomain(self: *Variable) void {
        std.mem.sort(i32, self._domain[0..self._length], {}, comptime std.sort.asc(i32));
    }
};

/// All variables to process
const Variables = []Variable;

/// Nary constraint
pub const NaryConstraint = struct { names: []const []const u8, constraint: *const (fn ([]i32) bool) };

/// All nary constraints
pub const NaryConstraints = []const NaryConstraint;

/// MinConflict Errors
pub const BackTrackingError = error{
    /// Invalid index reference in domain array
    InvalidIndex,
    /// Failure to remove a value from the domain
    RemoveDomainIndex,
    /// Specified variable is not defined in the variables array
    UndefinedVariable,
    /// Domain exhausted
    DomainExhausted,
};

/// Variable set to a specific value
const VariableValue = struct { name: []const u8, value: i32 };

/// Variable conflict state for a specific value
const VariableConflict = struct { name: []const u8, value: i32, conflict: bool };

/// Back-Tracking Solve result types
pub const SolveResultTag = enum {
    /// Variable values (if success)
    values,
    /// Variable values and conflicts (if failure)
    conflicts,
    /// Domain search exhausted
    exhausted,
};

/// Min Conflicts Solve result
pub const SolveResult = union(SolveResultTag) {
    /// Variable values (if success)
    values: []VariableValue,
    /// Variable values and conflicts (if failure)
    conflicts: []VariableConflict,
    /// Domain search exhausted
    exhausted,
};

////////////
// Functions

/// Initialize variable array to first domain value
/// (based on their respective domains)
/// variables - List of variables
/// variable_values - List of populated variables
pub fn initVariableValues(variables: Variables, variable_values: []VariableValue) !void {
    for (0.., variables) |i, v| {
        if (v.domain().len > 0) {
            variable_values[i] = VariableValue{ .name = v.name, .value = v.domain()[0] };
        }
    }
}

/// Determine if the variables, with their current values, have constraint
/// conflicts. The result is a array with each variable, its value, and if it
/// has a conflict with at least one constraint.
pub fn determineConflicts(allocator: std.mem.Allocator, variable_values: []VariableValue, constraints: NaryConstraints, variable_conflicts: []VariableConflict, index: ?usize) !void {
    // init all conflicts to false
    for (0.., variable_values) |i, v| {
        variable_conflicts[i] = .{ .name = v.name, .value = v.value, .conflict = false };
    }

    // Process all constraints.
    constraints: for (constraints) |constraint| {
        var values: []i32 = try allocator.alloc(i32, constraint.names.len);
        defer allocator.free(values);

        // Populate values for contraint (based on the name array)
        const index2 = index orelse variable_values.len - 1;
        for (0.., constraint.names) |ni, name| {
            // Only search against variables that are "active"
            // Since variables are processed in order of the array,
            // active indexes: 0 .. current variable
            var found_name = false;
            for (variable_values[0 .. index2 + 1]) |v| {
                if (std.mem.eql(u8, v.name, name)) {
                    values[ni] = v.value;
                    found_name = true;
                    break;
                }
            }
            if (!found_name) {
                // Could not find variable in the current active variables
                // This constraint cannot currently be applied
                continue :constraints;
            }
        }

        // Calculate contraint, if it fails, update the appropriate conflicts for all variables
        const result = constraint.constraint(values);
        if (!result) {
            for (constraint.names) |cn| {
                for (0.., variable_conflicts) |vci, vc| {
                    if (std.mem.eql(u8, vc.name, cn)) {
                        variable_conflicts[vci].conflict = true;
                    }
                }
            }
        }
    }
}

/// Solver for a specific variable
/// index - Index of target variable
pub fn solveVariable(allocator: std.mem.Allocator, variables: Variables, constraints: NaryConstraints, variable_values: []VariableValue, index: usize) !SolveResult {
    // iterate through my domain values
    for (variables[index].domain()) |v| {
        // set value for myself
        variable_values[index].value = v;
        //std.debug.print("solveVariable: [{d}] = {any}\n", .{ index, v });

        const variable_conflicts: []VariableConflict = try allocator.alloc(VariableConflict, variable_values.len);
        defer allocator.free(variable_conflicts);

        try determineConflicts(allocator, variable_values, constraints, variable_conflicts, index);

        // Determine if there are any conflicts
        var has_conflicts = false;
        for (variable_conflicts) |c| {
            if (c.conflict) {
                has_conflicts = true;
                break;
            }
        }

        if (!has_conflicts) {
            if (index == variables.len - 1) {
                // Found an answer, return it
                return SolveResult{ .values = variable_values };
            } else {
                // Ok so far, go deeper
                const child_result = try solveVariable(allocator, variables, constraints, variable_values, index + 1);
                switch (child_result) {
                    SolveResult.values => |_| {
                        // found answer, bubble it up
                        return child_result;
                    },
                    SolveResult.conflicts => |x| {
                        // Conflict found in child, don't continue
                        defer allocator.free(x);
                    },
                    SolveResult.exhausted => {
                        // Do nothing, child search is done
                    },
                }
            }
        }
    }

    return SolveResult.exhausted;
}

/// Back-Tracking solver
/// Provided with variables and contraints, attempt to find a solution
pub fn solve(allocator: std.mem.Allocator, variables: Variables, constraints: NaryConstraints) !SolveResult {
    // Initialize variable values/conflicts
    const variable_values: []VariableValue = try allocator.alloc(VariableValue, variables.len);
    try initVariableValues(variables, variable_values);
    const variable_conflicts: []VariableConflict = try allocator.alloc(VariableConflict, variable_values.len);
    try determineConflicts(allocator, variable_values, constraints, variable_conflicts, null);

    // iterate through variables, starting with the first one

    if (variables.len == 0) {
        defer allocator.free(variable_conflicts);
        return SolveResult{ .values = variable_values };
    }

    const result = try solveVariable(allocator, variables, constraints, variable_values, 0);

    switch (result) {
        SolveResult.values => |v| {
            defer allocator.free(variable_conflicts);
            return SolveResult{ .values = v };
        },
        SolveResult.conflicts => |c| {
            defer allocator.free(variable_values);
            return SolveResult{ .conflicts = c };
        },
        SolveResult.exhausted => {
            defer allocator.free(variable_values);
            defer allocator.free(variable_conflicts);
            return result;
        },
    }
}

////////
// Tests

test "init variable values" {
    const allocator = std.testing.allocator;

    var ad = [_]i32{ 1, 2, 3, 4, 5 };
    const a = Variable.init(.{ .name = "a", .domain = &ad });
    var bd = [_]i32{ 11, 12, 13, 14, 15 };
    const b = Variable.init(.{ .name = "b", .domain = &bd });
    var cd = [_]i32{ 21, 22, 23, 24, 25 };
    const c = Variable.init(.{ .name = "c", .domain = &cd });

    var variables = [_]Variable{ a, b, c };

    const variable_values = try allocator.alloc(VariableValue, variables.len);
    defer allocator.free(variable_values);

    try initVariableValues(&variables, variable_values);

    try std.testing.expect(variable_values[0].value == 1);
    try std.testing.expect(variable_values[1].value == 11);
    try std.testing.expect(variable_values[2].value == 21);
}

fn greaterThan(data: []i32) bool {
    return data[0] > data[1];
}

test "determine conflicts - no conflict" {
    const allocator = std.testing.allocator;

    var ad = [_]i32{ 1, 2, 3, 4, 5 };
    const a = Variable.init(.{ .name = "a", .domain = &ad });
    var bd = [_]i32{ 11, 12, 13, 14, 15 };
    const b = Variable.init(.{ .name = "b", .domain = &bd });
    var cd = [_]i32{ 21, 22, 23, 24, 25 };
    const c = Variable.init(.{ .name = "c", .domain = &cd });

    var variables = [_]Variable{ a, b, c };

    const variable_values = try allocator.alloc(VariableValue, variables.len);
    defer allocator.free(variable_values);

    const variable_conflicts = try allocator.alloc(VariableConflict, variables.len);
    defer allocator.free(variable_conflicts);

    const constraints = [_]NaryConstraint{
        NaryConstraint{ .names = &.{ "b", "a" }, .constraint = &greaterThan },
    };

    try initVariableValues(&variables, variable_values);
    try determineConflicts(allocator, variable_values, &constraints, variable_conflicts, 1);

    try std.testing.expect(variable_conflicts[0].conflict == false);
    try std.testing.expect(variable_conflicts[1].conflict == false);
}

test "determine conflicts - has conflict" {
    const allocator = std.testing.allocator;

    var ad = [_]i32{ 1, 2, 3, 4, 5 };
    const a = Variable.init(.{ .name = "a", .domain = &ad });
    var bd = [_]i32{ 11, 12, 13, 14, 15 };
    const b = Variable.init(.{ .name = "b", .domain = &bd });
    var cd = [_]i32{ 21, 22, 23, 24, 25 };
    const c = Variable.init(.{ .name = "c", .domain = &cd });

    var variables = [_]Variable{ a, b, c };

    const variable_values = try allocator.alloc(VariableValue, variables.len);
    defer allocator.free(variable_values);

    const variable_conflicts = try allocator.alloc(VariableConflict, variables.len);
    defer allocator.free(variable_conflicts);

    const constraints = [_]NaryConstraint{
        NaryConstraint{ .names = &.{ "a", "b" }, .constraint = &greaterThan },
    };

    try initVariableValues(&variables, variable_values);
    try determineConflicts(allocator, variable_values, &constraints, variable_conflicts, 1);

    try std.testing.expect(variable_conflicts[0].conflict == true);
    try std.testing.expect(variable_conflicts[1].conflict == true);
}
