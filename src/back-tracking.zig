//! Back-Tracking Constraint Solver
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
pub fn determineConflicts(allocator: std.mem.Allocator, variable_values: []VariableValue, constraints: NaryConstraints, index: ?usize) ![]VariableConflict {
    const variable_conflicts: []VariableConflict = try allocator.alloc(VariableConflict, variable_values.len);
    // defer allocator.free(variable_conflicts); // this is wrong
    for (0.., variable_values) |i, v| {
        // init all conflicts to false
        variable_conflicts[i] = .{ .name = v.name, .value = v.value, .conflict = false };
    }

    // Process all constraints.
    // Note: It would be more efficient to only process contraints for a
    // specific variable, but that involves a lot of tracking I don't want
    // to do right now
    constraints: for (constraints) |constraint| {
        var values: []i32 = try allocator.alloc(i32, constraint.names.len);
        defer allocator.free(values);

        // Populate values for contraint (based on the name array)

        const index2 = index orelse variable_values.len - 1; // - 1;
        for (0.., constraint.names) |ni, name| {
            // Only search against variables that are "active"
            // indexes: 0 - current variable
            var found_name = false;
            for (variable_values[0 .. index2 + 1]) |v| {
                // std.debug.print("{s} {s}\n", .{ name, v.name });
                // for (variable_values) |v| {
                if (std.mem.eql(u8, v.name, name)) {
                    values[ni] = v.value;
                    found_name = true;
                    break;
                }
            }
            if (!found_name) {
                // Could not find variable in the current active variables
                // This constraint cannot currently be applied
                std.debug.print("continuing for index: {d} ({any}) ni: {d}\n", .{ index2, index, ni });
                continue :constraints;
            }
        }

        // Calculate contraint, if it fails, update the appropriate conflicts
        const result = constraint.constraint(values);
        std.debug.print("determineConflicts: {any} {any} {any}\n", .{ constraint.constraint, result, values });

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

    // Init
    // var success = false;
    //var variable_conflicts = try determineConflicts(allocator, variable_values, constraints);

    // iterate through my domain values
    std.debug.print("solveVariable: [{d}]\n", .{index});

    for (me.domain()) |v| {
        // set value for myself
        variable_values[index].value = v;
        // std.debug.print("solveVariable: [{d}] = {any}\n", .{ index, variable_values[index] });
        std.debug.print("solveVariable: [{d}] = {any}\n", .{ index, v });

        const variable_conflicts = try determineConflicts(allocator, variable_values, constraints, index);
        //defer allocator.free(variable_conflicts);
        //std.debug.print("conflicts: {any}\n", .{&variable_conflicts});

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
                std.debug.print("done\n", .{});
                defer allocator.free(variable_conflicts);
                return SolveResult{ .values = variable_values };
            } else {
                // Ok so far, go deeper
                std.debug.print("deeper [{d}]\n", .{index});

                const result2 = try solveVariable(allocator, variables, constraints, variable_values, index + 1);
                std.debug.print("result2: {any}\n", .{result2});
                switch (result2) {
                    SolveResult.values => |_| {
                        // std.debug.print("values: {any}\n", .{x});
                        // defer allocator.free(x);
                        //defer allocator.free(x.conflicts);
                        // found answer, bubble it up
                        return result2;
                    },
                    SolveResult.conflicts => |x| {
                        // Conflicts, don't continue
                        // std.debug.print("conflicts: {any}\n", .{x});
                        //return result2;
                        // conflict found in child
                        defer allocator.free(x);
                    },
                    SolveResult.exhausted => {
                        // Do nothing, child search is done
                    },
                }
            }
        }
    }

    // No answer found for this variable
    // ???? variable_values[index].value = null;

    // defer allocator.free(variable_values);
    // return SolveResult{ .conflicts = variable_conflicts };
    // return BackTrackingError.DomainExhausted;
    return SolveResult.exhausted;
}

/// Back-Tracking solver
/// Provided with variables and contraints, attempt to find a solution
pub fn solve(allocator: std.mem.Allocator, variables: Variables, constraints: NaryConstraints) !SolveResult {
    // const ts: u128 = @bitCast(std.time.nanoTimestamp());
    // const seed: u64 = @truncate(ts);
    // var prng = std.rand.DefaultPrng.init(seed);
    // const rand = prng.random();

    std.debug.print("solve:\n", .{});

    // Init
    // var success = false;

    // Initialize variable values/conflicts
    const variable_values = try initVariableValues(allocator, variables);
    // zzz defer allocator.free(variable_values); // this is wrong
    const variable_conflicts = try determineConflicts(allocator, variable_values, constraints, null);
    // defer allocator.free(variable_conflicts); // this is wrong

    // iterate through variables

    std.debug.print("l: {any}\n", .{variables});

    if (variables.len == 0) {
        defer allocator.free(variable_conflicts);
        return SolveResult{ .values = variable_values };
    }

    const result = try solveVariable(allocator, variables, constraints, variable_values, 0);

    switch (result) {
        SolveResult.values => |v| {
            std.debug.print("success\n", .{});
            defer allocator.free(variable_conflicts);
            return SolveResult{ .values = v };
        },
        SolveResult.conflicts => |c| {
            std.debug.print("failure\n", .{});
            defer allocator.free(variable_values);
            return SolveResult{ .conflicts = c };
        },
        SolveResult.exhausted => {
            return result;
        },
    }
}

////////
// Tests

fn greaterThan(data: []const i32) bool {
    return data[0] > data[1];
}

fn isDouble(data: []const i32) bool {
    return data[0] == data[1] * 2;
}

test "placeholder" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.deinit(); // put back in to track leaks/frees
    const allocator = gpa.allocator();

    std.debug.print("\n", .{});

    var ad = [_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    const a = Variable.init(.{ .name = "a", .domain = &ad });
    var bd = [_]i32{ 1, 2, 3, 4, 5 };
    const b = Variable.init(.{ .name = "b", .domain = &bd });

    var variables = [_]Variable{ a, b };
    var constraints = [_]NaryConstraint{ NaryConstraint{ .names = &[_][]const u8{ "a", "b" }, .constraint = &greaterThan }, NaryConstraint{ .names = &[_][]const u8{ "a", "b" }, .constraint = &isDouble } };

    const result = solve(allocator, &variables, &constraints) catch |err| {
        std.debug.print("failure: {any}\n", .{err});
        return;
    };

    switch (result) {
        SolveResult.values => |x| {
            defer allocator.free(result.values);
            std.debug.print("success: {any}\n", .{x});
        },
        SolveResult.conflicts => |x| {
            defer allocator.free(result.conflicts);
            std.debug.print("failure: {any}\n", .{x});
        },
        SolveResult.exhausted => {
            std.debug.print("failure: search exhausted\n", .{});
        },
    }

    try std.testing.expect(1 == 1);
}
