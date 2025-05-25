//! Back-Tracking Constraint Solver
//! Given variables and constraints, attempt to find a solution

const cmn = @import("common");
const std = @import("std");
const random = std.crypto.random;
const testing = std.testing;

////////
// Types

/// Variable ordering method
pub const VariableOrder = enum {
    /// Process variables with highest degree (# of constraints) first
    maximum_degree,
    /// Process variables with smallest domain first
    minimum_domain_size,
};

/// Solver configuration
pub const Config = struct {
    variable_order: VariableOrder,
};

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

/////////////
// Heuristics

// TODO: Potentially move to another file

/// Determine variable domain size
/// This is the number of values in the variable's domain
pub fn variableDomainLength(variable: Variable) i32 {
    const len: i32 = @intCast(variable.domain().len);
    return len;
}

/// Determine variable degree
/// This is the number of constraints the variable belongs to
pub fn variableDegree(variable: Variable, constraints: NaryConstraints) i32 {
    var count: i32 = 0;
    for (constraints) |constraint| {
        if (cmn.contains([]const u8, constraint.names, variable.name)) {
            count += 1;
        }
    }
    return count;
}
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
/// allocator - Allocator
/// variable_variables - Current variable values
/// constraints - Constraints to evaluate
/// variable_conflicts - Results of the contraint evaluation
/// variable_order - Order of current and future variables to process
pub fn determineConflicts(allocator: std.mem.Allocator, variable_values: []VariableValue, constraints: NaryConstraints, variable_conflicts: []VariableConflict, variable_order: []usize) !void {
    // init all conflicts to false
    for (0.., variable_values) |i, v| {
        variable_conflicts[i] = .{ .name = v.name, .value = v.value, .conflict = false };
    }

    // Process all constraints.
    constraints: for (constraints) |constraint| {
        var values: []i32 = try allocator.alloc(i32, constraint.names.len);
        defer allocator.free(values);

        // Populate values for constraint (based on the name array)
        for (0.., constraint.names) |ni, name| {
            // Only search against variables that are "active"
            // variable_order is the current variable + future variables
            // So "active/set" variables are not in this list
            var found_name = false;
            for (0.., variable_values) |vvi, v| {
                if ((variable_order.len == 0) or (std.mem.indexOfScalar(usize, variable_order[1..], vvi) == null)) {
                    // If it is not in the processing list, it is active
                    if (std.mem.eql(u8, v.name, name)) {
                        values[ni] = v.value;
                        found_name = true;
                        break;
                    }
                }
            }
            if (!found_name) {
                // Could not find variable in the current active variables
                // This constraint cannot currently be applied
                continue :constraints;
            }
        }

        // Calculate constraint, if it fails, update the appropriate conflicts for all variables
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
pub fn solveVariable(allocator: std.mem.Allocator, variables: Variables, constraints: NaryConstraints, variable_values: []VariableValue, variable_order: []usize) !SolveResult {
    if (variable_order.len == 0) {
        // At end of processing
        return SolveResult{ .values = variable_values };
    }

    const index = variable_order[0];

    // iterate through my domain values
    for (variables[index].domain()) |v| {
        // set value for myself
        variable_values[index].value = v;
        //std.debug.print("solveVariable: [{d}] = {any}\n", .{ index, v });

        const variable_conflicts: []VariableConflict = try allocator.alloc(VariableConflict, variable_values.len);
        defer allocator.free(variable_conflicts);

        try determineConflicts(allocator, variable_values, constraints, variable_conflicts, variable_order);

        // Determine if there are any conflicts
        var has_conflicts = false;
        for (variable_conflicts) |c| {
            if (c.conflict) {
                has_conflicts = true;
                break;
            }
        }

        if (!has_conflicts) {
            if (variable_order.len == 0) {
                // if (index == variables.len - 1) {
                // Found an answer, return it
                return SolveResult{ .values = variable_values };
            } else {
                // Ok so far, go deeper
                const child_result = try solveVariable(allocator, variables, constraints, variable_values, variable_order[1..]); // index + 1);
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

/// Comparer: Use domain size
/// context: Variables object (indexable by variable index)
fn lessThanDomainSize(context: Variables, a: usize, b: usize) bool {
    return context[a].domain().len < context[b].domain().len;
}

/// Comparer: Use degree
/// context: hash(K=variable index, V=number of constraints)
fn greaterThanDegree(context: std.array_hash_map.ArrayHashMapWithAllocator(usize, usize, std.array_hash_map.AutoContext(usize), false), a: usize, b: usize) bool {
    // Reverse sort
    return context.get(a) orelse 0 > context.get(b) orelse 0;
}

/// Back-Tracking solver
/// Provided with variables and contraints, attempt to find a solution
pub fn solve(allocator: std.mem.Allocator, config: Config, variables: Variables, constraints: NaryConstraints) !SolveResult {
    // Initialize variable values/conflicts
    const variable_values: []VariableValue = try allocator.alloc(VariableValue, variables.len);
    try initVariableValues(variables, variable_values);
    const variable_conflicts: []VariableConflict = try allocator.alloc(VariableConflict, variable_values.len);
    const empty_list: []usize = &[_]usize{};
    try determineConflicts(allocator, variable_values, constraints, variable_conflicts, empty_list);

    // iterate through variables, starting with the first one

    if (variables.len == 0) {
        defer allocator.free(variable_conflicts);
        return SolveResult{ .values = variable_values };
    }

    // Determine variable processing order
    const variable_order = try allocator.alloc(usize, variables.len);
    // Init - By default, process variables in order defined
    for (0..variables.len) |i| {
        variable_order[i] = i;
    }

    switch (config.variable_order) {
        VariableOrder.maximum_degree => {
            // Process variables in order of maximum degree (contraint involvement)
            var variable_degree = std.array_hash_map.AutoArrayHashMap(usize, usize).init(allocator);

            for (0.., variables) |variable_index, variable| {
                var constraint_count: usize = 0;
                // Count number of contraints variable belongs to
                for (constraints) |constraint| {
                    for (constraint.names) |constraint_name| {
                        if (std.mem.eql(u8, constraint_name, variable.name)) {
                            constraint_count += 1;
                            break;
                        }
                    }
                }
                try variable_degree.put(variable_index, constraint_count);
            }

            std.sort.block(usize, variable_order, variable_degree, greaterThanDegree);
        },
        VariableOrder.minimum_domain_size => {
            // Process variables in order of smallest to largest domain size
            std.sort.block(usize, variable_order, variables, lessThanDomainSize);
        },
    }

    const result = try solveVariable(allocator, variables, constraints, variable_values, variable_order);

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

// heuristics begin

test "variable domain length - 0" {
    var d = [_]i32{};
    const v = Variable.init(.{ .name = "five", .domain = &d });

    const result = variableDomainLength(v);
    try std.testing.expect(result == 0);
}

test "variable domain length - 5" {
    var d = [_]i32{ 1, 2, 3, 4, 5 };
    const v = Variable.init(.{ .name = "five", .domain = &d });

    const result = variableDomainLength(v);
    try std.testing.expect(result == 5);
}

test "variable constraint degree - 0" {
    var ad = [_]i32{ 1, 2, 3, 4, 5 };
    const a = Variable.init(.{ .name = "a", .domain = &ad });

    const constraints = [_]NaryConstraint{
        NaryConstraint{ .names = &.{ "b", "c" }, .constraint = &greaterThan },
        NaryConstraint{ .names = &.{ "c", "c" }, .constraint = &greaterThan },
        NaryConstraint{ .names = &.{ "b", "b" }, .constraint = &greaterThan },
        NaryConstraint{ .names = &.{ "b", "b" }, .constraint = &greaterThan },
        NaryConstraint{ .names = &.{ "c", "c" }, .constraint = &greaterThan },
    };

    const result = variableDegree(a, &constraints);

    try std.testing.expect(result == 0);
}

test "variable constraint degree - 0 - empty" {
    var ad = [_]i32{ 1, 2, 3, 4, 5 };
    const a = Variable.init(.{ .name = "a", .domain = &ad });

    const constraints = [_]NaryConstraint{};

    const result = variableDegree(a, &constraints);

    try std.testing.expect(result == 0);
}

test "variable constraint degree - 3" {
    var ad = [_]i32{ 1, 2, 3, 4, 5 };
    const a = Variable.init(.{ .name = "a", .domain = &ad });

    const constraints = [_]NaryConstraint{
        NaryConstraint{ .names = &.{ "b", "a" }, .constraint = &greaterThan },
        NaryConstraint{ .names = &.{ "a", "a" }, .constraint = &greaterThan },
        NaryConstraint{ .names = &.{ "b", "b" }, .constraint = &greaterThan },
        NaryConstraint{ .names = &.{ "b", "b" }, .constraint = &greaterThan },
        NaryConstraint{ .names = &.{ "a", "a" }, .constraint = &greaterThan },
    };

    const result = variableDegree(a, &constraints);

    try std.testing.expect(result == 3);
}

// heuristics end

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

    const variable_order = try allocator.alloc(usize, variables.len);
    defer allocator.free(variable_order);
    for (0..variables.len) |i| {
        variable_order[i] = i;
    }

    try initVariableValues(&variables, variable_values);
    try determineConflicts(allocator, variable_values, &constraints, variable_conflicts, variable_order);

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

    const variable_order = try allocator.alloc(usize, variables.len - 1);
    defer allocator.free(variable_order);
    for (0..variables.len - 1) |i| {
        variable_order[i] = i + 1;
    }
    // 1,2

    try initVariableValues(&variables, variable_values);
    try determineConflicts(allocator, variable_values, &constraints, variable_conflicts, variable_order);

    try std.testing.expect(variable_conflicts[0].conflict == true);
    try std.testing.expect(variable_conflicts[1].conflict == true);
}
