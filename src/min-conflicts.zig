//! Min Conflicts Constraint Solver
//! Given variables and constraints, attempt to find a solution

const std = @import("std");
const random = std.crypto.random;
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

    /// Create a variable
    pub fn init(data: struct { name: []const u8, domain: Domain }) Variable {
        // Variable
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
            return MinConflictsError.InvalidIndex;
        }

        // Shift everything left and reduce length by one
        for (index..(self._length - 1)) |i| {
            self._domain[i] = self._domain[i + 1];
        }

        self._length -= 1;
    }

    /// Shuffle domain values
    pub fn shuffleDomain(self: *Variable) void {
        std.Random.shuffle(random, i32, self._domain[0..self._length]);
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
pub const MinConflictsError = error{
    /// Invalid index reference in domain array
    InvalidIndex,
    /// Failure to remove a value from the domain
    RemoveDomainIndex,
    /// Specified variable is not defined in the variables array
    UndefinedVariable,
};

/// Variable set to a specific value
const VariableValue = struct { name: []const u8, value: i32 };

/// Variable conflict state for a specific value
const VariableConflict = struct { name: []const u8, value: i32, conflict: bool };

/// Min Conflicts Solve result types
pub const SolveResultTag = enum {
    /// Variable values (if success)
    values,
    /// Variable values and conflicts (if failure)
    conflicts,
};

/// Min Conflicts Solve result
pub const SolveResult = union(SolveResultTag) {
    /// Variable values (if success)
    values: []VariableValue,
    /// Variable values and conflicts (if failure)
    conflicts: []VariableConflict,
};

////////////
// Functions

/// Initialize variable array to randomized values
/// (based on their respective domains)
pub fn initVariableValues(allocator: std.mem.Allocator, variables: Variables) ![]VariableValue {
    const variable_values: []VariableValue = try allocator.alloc(VariableValue, variables.len);

    for (0.., variables) |i, v| {
        const index = random.intRangeAtMost(usize, 0, v.domain().len - 1);
        variable_values[i] = VariableValue{ .name = v.name, .value = v.domain()[index] };
    }
    return variable_values;
}

/// Determine if the variables, with their current values, have constraint
/// conflicts. The result is a array with each variable, its value, and if it
/// has a conflict with at least one constraint.
pub fn determineConflicts(allocator: std.mem.Allocator, variable_values: []VariableValue, constraints: NaryConstraints) ![]VariableConflict {
    const variable_conflicts: []VariableConflict = try allocator.alloc(VariableConflict, variable_values.len);
    for (0.., variable_values) |i, v| {
        // init all conflicts to false
        variable_conflicts[i] = .{ .name = v.name, .value = v.value, .conflict = false };
    }

    // Process all constraints.
    // Note: It would be more efficient to only process contrains for a
    // specific variable, but that involves a lot of tracking I don't want
    // to do right now
    for (constraints) |constraint| {
        var values: []i32 = try allocator.alloc(i32, constraint.names.len);
        defer allocator.free(values);

        // Populate values for contraint (based on the name array)
        for (0.., constraint.names) |ni, name| {
            for (variable_values) |v| {
                if (std.mem.eql(u8, v.name, name)) {
                    values[ni] = v.value;
                    break;
                }
            }
        }

        // Calculate contraint, if it fails, update the appropriate conflicts
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

    return variable_conflicts;
}

/// Select a random index from conflicted variables
fn getRandomConflictIndex(allocator: std.mem.Allocator, conflicts: []VariableConflict) !?usize {
    var indexes = std.ArrayList(usize).init(allocator);
    defer indexes.deinit();

    for (0.., conflicts) |i, c| {
        if (c.conflict) {
            try indexes.append(i);
        }
    }

    // There are no conflicted variables
    if (indexes.items.len == 0) {
        return null;
    }

    const i = random.intRangeAtMost(usize, 0, indexes.items.len - 1);
    return indexes.items[i];
}

/// Count number of true values in an array
fn countTrues(conflicts: []VariableConflict) i32 {
    var count: i32 = 0;
    for (conflicts) |conflict| {
        if (conflict.conflict) {
            count += 1;
        }
    }
    return count;
}

/// Min Conflicts solver
/// Provided with variables and contraints, attempt to find a solution
pub fn solve(allocator: std.mem.Allocator, max_rounds: i32, variables: Variables, constraints: NaryConstraints) !SolveResult {
    // Init
    var success = false;

    // Initialize variable values/conflicts
    const variable_values = try initVariableValues(allocator, variables);
    var variable_conflicts = try determineConflicts(allocator, variable_values, constraints);

    // Check success status
    success = true;
    for (variable_conflicts) |x| {
        if (x.conflict) {
            success = false;
            break;
        }
    }

    var best_conflicts_count = countTrues(variable_conflicts);
    var current_round: i32 = 0;
    while ((!success) and (best_conflicts_count > 0) and (current_round < max_rounds)) : (current_round += 1) {
        // Get random variable with a conflict
        if (try getRandomConflictIndex(allocator, variable_conflicts)) |target_index| {
            best_conflicts_count = countTrues(variable_conflicts);
            var best_domain_value = variable_values[target_index].value;

            // Shuffle domain to avoid rounds pushing values to the edge of the
            // domain. This might not be strictly required, but this seems to
            // provide better results.
            variables[target_index].shuffleDomain();

            // Iterate through all domain values for the variable
            // Find the value that minimizes conflicts
            for (variables[target_index].domain()) |domain_value| {
                variable_values[target_index].value = domain_value;

                const temp_conflicts = try determineConflicts(allocator, variable_values, constraints);
                defer allocator.free(temp_conflicts);

                const temp_conflicts_count = countTrues(temp_conflicts);

                // If better or equal with random chance, consider this an improvement
                if ((temp_conflicts_count < best_conflicts_count) or ((temp_conflicts_count == best_conflicts_count) and (random.intRangeAtMost(u64, 0, 10) < 5))) {
                    best_conflicts_count = temp_conflicts_count;
                    best_domain_value = domain_value;
                    for (0.., variable_conflicts) |i, _| {
                        variable_conflicts[i] = temp_conflicts[i];
                    }
                }
            }

            variable_values[target_index].value = best_domain_value;
        }

        // Check success status
        success = true;
        for (variable_conflicts) |x| {
            if (x.conflict) {
                success = false;
                break;
            }
        }
    }

    if (success) {
        defer allocator.free(variable_conflicts);
        return SolveResult{ .values = variable_values };
    } else {
        defer allocator.free(variable_values);
        return SolveResult{ .conflicts = variable_conflicts };
    }
}

////////
// Tests

test "domain shuffle - length" {
    var domain = [_]i32{ 1, 2, 3, 4, 5, 6, 7, 8 };
    var v = Variable.init(.{ .name = "v", .domain = &domain });

    // Check length
    const lenBefore = v.domain().len;
    v.shuffleDomain();
    try testing.expect(v.domain().len == lenBefore);
}
//
test "domain shuffle - remove index" {
    var domain = [_]i32{ 1, 2, 3, 4, 5, 6, 7, 8 };
    var v = Variable.init(.{ .name = "v", .domain = &domain });

    // Check length
    try v.removeDomainIndex(6);
    try v.removeDomainIndex(3);
    const lenBefore = v.domain().len;
    v.shuffleDomain();
    try testing.expect(v.domain().len == lenBefore);

    // Check values post delete
    v.sortDomain();
    try testing.expect(std.mem.eql(i32, v.domain(), &[_]i32{ 1, 2, 3, 5, 6, 8 }));
}
