//! Back-Jumping Constraint Solver
//! Given variables and constraints, attempt to find a solution

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
            return BackJumpingError.InvalidIndex;
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
pub const BackJumpingError = error{
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
    // const rand = newRandom();
    const ts: u128 = @bitCast(std.time.nanoTimestamp());
    const seed: u64 = @truncate(ts);
    var prng = std.rand.DefaultPrng.init(seed);
    const rand = prng.random();

    const variable_values: []VariableValue = try allocator.alloc(VariableValue, variables.len);

    for (0.., variables) |i, v| {
        const index = rand.intRangeAtMost(usize, 0, v.domain().len - 1);
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

pub fn solveVariable(allocator: std.mem.Allocator, variables: Variables, constraints: NaryConstraints, variable_values: []VariableValue, index: usize) !SolveResult {
    const me = variables[index];

    // iterate through my domain values
    for (me.domain()) |v| {
        // set value for myself
        variable_values[index].value = v;

        const conflicts = determineConflicts(allocator, variable_values, constraints);
        std.debug.print("conflicts: {any}\n", .{conflicts});
    }
}

/// Back-Jumping solver
/// Provided with variables and contraints, attempt to find a solution
pub fn solve(allocator: std.mem.Allocator, variables: Variables, constraints: NaryConstraints) !SolveResult {
    const ts: u128 = @bitCast(std.time.nanoTimestamp());
    const seed: u64 = @truncate(ts);
    var prng = std.rand.DefaultPrng.init(seed);
    const rand = prng.random();

    // Init
    var success = false;

    // Initialize variable values/conflicts
    const variable_values = try initVariableValues(allocator, variables);
    var variable_conflicts = try determineConflicts(allocator, variable_values, constraints);

    // iterate through variables
    var current_variable_index: usize = 0;
    while (current_variable_index < variables.len) {
        std.debug.print("solve: processing: {d}\n", .{current_variable_index});
        std.debug.print("solve: {any}\n", .{variables[current_variable_index]});

        current_variable_index += 1;
    }

    if (1 == 1) {
        variable_values[0].name = "foo";
        variable_conflicts[0].name = "foo";
        success = false;
        std.debug.print("{}\n", .{rand.intRangeAtMost(usize, 0, 10)});
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

fn greaterThan(data: []const i32) bool {
    return data[0] > data[1];
}

fn isDouble(data: []const i32) bool {
    return data[0] * 2 == data[1];
}

test "placeholder" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ad = [_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    const a = Variable.init(.{ .name = "a", .domain = &ad });
    var bd = [_]i32{ 1, 2, 3, 4, 5 };
    const b = Variable.init(.{ .name = "b", .domain = &bd });

    var variables = [_]Variable{ a, b };
    var constraints = [_]NaryConstraint{ NaryConstraint{ .names = &[_][]const u8{ "a", "b" }, .constraint = &greaterThan }, NaryConstraint{ .names = &[_][]const u8{ "a", "b" }, .constraint = &isDouble } };

    const result = try solve(allocator, &variables, &constraints);
    switch (result) {
        SolveResult.values => |x| {
            defer allocator.free(x);
            std.debug.print("success: {any}\n", .{x});
        },
        SolveResult.conflicts => |x| {
            defer allocator.free(x);
            std.debug.print("failure: {any}\n", .{x});
        },
    }

    try std.testing.expect(1 == 1);
}
