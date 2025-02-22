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
pub const MinConflictsError = error{
    /// Invalid index reference in domain array
    InvalidIndex,
    /// Failure to remove a value from the domain
    RemoveDomainIndex,
    /// Specified variable is not defined in the variables array
    UndefinedVariable,
};

// //var prng = std.rand.DefaultPrng.init(123);
// var prng = std.rand.DefaultPrng.init(blk: {
// var seed: u64 = undefined;
// try std.posix.getrandom(std.mem.asBytes(&seed));
// break :blk seed;
// });
// //const random = std.crypto.random;
// const random = prng.random();
//     return random;
//
// fn newRandom() std.Random {
//     const ts: u128 = @bitCast(std.time.nanoTimestamp());
//     const seed: u64 = @truncate(ts);
//     std.debug.print("{any}\n", .{seed});
//     var prng = std.rand.DefaultPrng.init(seed);
//     return prng.random();
// }
//
////////////
// Functions

const VariableValue = struct { name: []const u8, value: i32 };
const VariableConflict = struct { name: []const u8, value: i32, conflict: bool };

/// Initialize variable array to randomized values
/// (based on their respective domains)
pub fn initVariableValues(allocator: std.mem.Allocator, variables: Variables) ![]VariableValue {
    // const rand = newRandom();
    const ts: u128 = @bitCast(std.time.nanoTimestamp());
    const seed: u64 = @truncate(ts);
    std.debug.print("{any}\n", .{seed});
    var prng = std.rand.DefaultPrng.init(seed);
    const rand = prng.random();

    const variable_values: []VariableValue = try allocator.alloc(VariableValue, variables.len);

    //var prng = std.rand.DefaultPrng.init(123);
    // var prng = std.rand.DefaultPrng.init(blk: {
    //     var seed: u64 = undefined;
    //     try std.posix.getrandom(std.mem.asBytes(&seed));
    //     break :blk seed;
    // });
    //const random = std.crypto.random;
    // const random = prng.random();

    for (0.., variables) |i, v| {
        const index = rand.intRangeAtMost(usize, 0, v.domain().len - 1);
        variable_values[i] = VariableValue{ .name = v.name, .value = v.domain()[index] };
    }
    return variable_values;
}

pub fn initVariableConflicts(allocator: std.mem.Allocator, variables: []VariableValue, constraints: NaryConstraints) ![]VariableConflict {
    const variable_conflicts: []VariableConflict = try allocator.alloc(VariableConflict, variables.len);

    std.debug.print("initVariableConflicts: start #######################\n", .{});
    defer std.debug.print("initVariableConflicts: end #####################\n", .{});

    // Init variable conflicts
    for (0.., variables) |i, v| {
        variable_conflicts[i] = VariableConflict{ .name = v.name, .value = v.value, .conflict = false };
    }

    for (0.., variables) |i, _| {
        const temp = try determineConflicts(allocator, i, variables, constraints, variable_conflicts);
        for (0.., temp) |j, t| {
            variable_conflicts[j].conflict = t.conflict;
        }
    }

    return variable_conflicts;
}

pub fn containsString(list: []const []const u8, s: []const u8) bool {
    for (list) |x| {
        if (std.mem.eql(u8, x, s)) {
            return true;
        }
    }
    return false;
}

pub fn determineConflicts(allocator: std.mem.Allocator, target_index: usize, variable_values: []VariableValue, constraints: NaryConstraints, starting_conflicts: []VariableConflict) ![]VariableConflict {
    const variable_conflicts: []VariableConflict = try allocator.alloc(VariableConflict, variable_values.len);
    _ = starting_conflicts;
    for (0.., variable_values) |i, v| {
        // variable_conflicts[i] = .{ .name = v.name, .value = v.value, .conflict = starting_conflicts[i].conflict };
        // init all conflicts to false
        variable_conflicts[i] = .{ .name = v.name, .value = v.value, .conflict = false };
    }

    const target_variable = variable_values[target_index];
    for (0.., constraints) |ci, constraint| {
        _ = ci;
        std.debug.print("checking: {s} vs {s}\n", .{ target_variable.name, constraint.names });

        // for now, just process all constraints. it's wasteful, but
        // otherwise I need to track the changing of conflicts
        if (true) {
            // if (containsString(constraint.names, target_variable.name)) {
            std.debug.print("{s} in {s} {any}\n", .{ target_variable.name, constraint.names, constraint.constraint });

            // TODO: THIS IS WRONG
            var values: []i32 = try allocator.alloc(i32, constraint.names.len);
            defer allocator.free(values);

            for (0.., constraint.names) |ni, name| {
                for (variable_values) |v| {
                    if (std.mem.eql(u8, v.name, name)) {
                        values[ni] = v.value;
                        break;
                    }
                }
            }
            std.debug.print("values: {d}\n", .{values});
            const result = constraint.constraint(values);
            if (!result) {
                std.debug.print("  constraint failed\n", .{});
                for (constraint.names) |cn| {
                    for (0.., variable_conflicts) |vci, vc| {
                        if (std.mem.eql(u8, vc.name, cn)) {
                            std.debug.print("determineConflicts: i: {} {s} {d} {}\n", .{ vci, vc.name, vc.value, vc.conflict });
                            variable_conflicts[vci].conflict = true;
                        }
                    }
                }
            } else {
                std.debug.print("  constraint success\n", .{});
            }
        }
    }

    return variable_conflicts;
}

/// Select a random index from conflicted variables
fn getRandomConflictIndex(allocator: std.mem.Allocator, conflicts: []VariableConflict) !?usize {
    // std.debug.print("getRandomConflictIndex: start ##################3\n", .{});
    // defer std.debug.print("getRandomConflictIndex: end ##################\n", .{});

    const ts: u128 = @bitCast(std.time.nanoTimestamp());
    const seed: u64 = @truncate(ts);
    var prng = std.rand.DefaultPrng.init(seed);
    const rand = prng.random();

    var indexes = std.ArrayList(usize).init(allocator);
    defer indexes.deinit();

    for (0.., conflicts) |i, c| {
        if (c.conflict) {
            try indexes.append(i);
        }
    }

    // std.debug.print("getRandomConflictIndex: {any}\n", .{indexes.items});

    // There are no conflicted variables
    if (indexes.items.len == 0) {
        return null;
    }

    const i = rand.intRangeAtMost(usize, 0, indexes.items.len - 1);
    // std.debug.print("getRandomConflictIndex: selected {d} => {d} \n", .{ i, indexes.items[i] });
    return indexes.items[i];
}

fn countTrues(conflicts: []VariableConflict) i32 {
    var count: i32 = 0;
    for (conflicts) |conflict| {
        if (conflict.conflict) {
            count += 1;
        }
    }
    return count;
}

pub const SolveResultTag = enum {
    values,
    conflicts,
};

pub const SolveResult = union(SolveResultTag) {
    values: []VariableValue,
    conflicts: []VariableConflict,
};

// pub fn solve(allocator: std.mem.Allocator, max_rounds: i32, variables: Variables, constraints: NaryConstraints) !struct { success: bool, values: []VariableValue, conflicts: []VariableConflict } {
pub fn solve(allocator: std.mem.Allocator, max_rounds: i32, variables: Variables, constraints: NaryConstraints) !SolveResult {
    // const rand = newRandom();
    const ts: u128 = @bitCast(std.time.nanoTimestamp());
    const seed: u64 = @truncate(ts);
    std.debug.print("solve: seed {d}\n", .{seed});
    var prng = std.rand.DefaultPrng.init(seed);
    const rand = prng.random();

    // Init
    var success = false;

    const variable_values = try initVariableValues(allocator, variables);
    // defer allocator.free(variable_values);

    var variable_conflicts = try initVariableConflicts(allocator, variable_values, constraints);
    // defer allocator.free(variable_conflicts);

    // Check success status
    success = true;
    for (variable_conflicts) |x| {
        if (x.conflict) {
            success = false;
            break;
        }
    }

    std.debug.print("solve: VALUE CHECK (success: {}) \n", .{success});
    for (variable_values) |x| {
        std.debug.print("solve: value   : {s} {d}\n", .{ x.name, x.value });
    }
    for (variable_conflicts) |x| {
        std.debug.print("solve: conflict: {s} {d} {}\n", .{ x.name, x.value, x.conflict });
    }

    std.debug.print("# DEBUG MARKER\n", .{});
    std.debug.print("#####################################################\n", .{});

    var best_conflicts_count = countTrues(variable_conflicts);
    var current_round: i32 = 0;
    while ((!success) and (best_conflicts_count > 0) and (current_round < max_rounds)) : (current_round += 1) {
        std.debug.print("solve: Round {d} of {d}\n", .{ current_round, max_rounds });

        // Get random variable with a conflict
        if (try getRandomConflictIndex(allocator, variable_conflicts)) |target_index| {
            best_conflicts_count = countTrues(variable_conflicts);
            var best_domain_value = variable_values[target_index].value;

            std.debug.print("before: {d}\n", .{variables[target_index].domain()});
            // Shuffle domain to avoid rounds pushing values to the edge of the
            // domain. This might not be strictly required, but this seems to
            // provide better results.
            variables[target_index].shuffleDomain();
            std.debug.print("after : {d}\n", .{variables[target_index].domain()});

            // Iterate through all domain values to minimize conflicts
            std.debug.print("###\n# Domain test for {s} (index: {})\n", .{ variables[target_index].name, target_index });
            for (variables[target_index].domain()) |domain_value| {
                variable_values[target_index].value = domain_value;

                const temp_conflicts = try determineConflicts(allocator, target_index, variable_values, constraints, variable_conflicts);
                defer allocator.free(temp_conflicts);

                const temp_conflicts_count = countTrues(temp_conflicts);

                for (temp_conflicts) |x| {
                    std.debug.print("tempc: {s} {d} {}\n", .{ x.name, x.value, x.conflict });
                }

                std.debug.print("compare: {d} {d}\n", .{ temp_conflicts_count, best_conflicts_count });

                if ((temp_conflicts_count < best_conflicts_count) or ((temp_conflicts_count == best_conflicts_count) and (rand.intRangeAtMost(u64, 0, 10) < 5))) {
                    std.debug.print("* improving from {d} to {d}\n", .{ best_conflicts_count, temp_conflicts_count });
                    best_conflicts_count = temp_conflicts_count;
                    best_domain_value = domain_value;
                    for (0.., variable_conflicts) |i, _| {
                        variable_conflicts[i] = temp_conflicts[i];
                    }
                    // for (variable_conflicts) |x| {
                    //     std.debug.print("conflicts: {any}\n", .{x});
                    // }
                } else {
                    std.debug.print("no improvement\n", .{});
                }
                for (variable_conflicts) |x| {
                    std.debug.print("conflictz: {s} {d} {}\n", .{ x.name, x.value, x.conflict });
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

    std.debug.print("###\n# FINAL CONFLICTS\n", .{});
    for (variable_conflicts) |x| {
        std.debug.print("conflicts: {s} {d} {}\n", .{ x.name, x.value, x.conflict });
    }

    // return .{ .success = success, .values = variable_values, .conflicts = variable_conflicts };
    if (success) {
        defer allocator.free(variable_conflicts);
        return SolveResult{ .values = variable_values };
    } else {
        defer allocator.free(variable_values);
        return SolveResult{ .conflicts = variable_conflicts };
    }

    // return .{ .success = success, .values = variable_values, .conflicts = variable_conflicts };
}

////////
// Tests

test "placeholder" {
    try testing.expect(1 == 1);
}

fn isEven(values: []i32) bool {
    for (values) |v| {
        if (@mod(v, 2) != 0) {
            return false;
        }
    }
    return true;
}
fn isOdd(values: []i32) bool {
    for (values) |v| {
        if (@mod(v, 2) == 0) {
            return false;
        }
    }
    return true;
}

test "testing" {
    // const allocator = std.testing.allocator;
    // const allocator = std.heap.ArenaAllocator(std.heap.PageAllocator);
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ad = [_]i32{ 1, 2, 3, 4, 5 };
    const a = Variable.init(.{ .name = "aa", .domain = &ad });

    var bd = [_]i32{ 11, 22, 33, 44, 55 };
    const b = Variable.init(.{ .name = "bb", .domain = &bd });

    var cd = [_]i32{ 111, 222, 333, 444, 555 };
    const c = Variable.init(.{ .name = "cc", .domain = &cd });

    var variables = [_]Variable{ a, b, c };

    const constraints = [_]NaryConstraint{
        // NaryConstraint{ .names = &[_][]const u8{ "aa", "bb" }, .constraint = &isEven },
        NaryConstraint{ .names = &[_][]const u8{"aa"}, .constraint = &isEven },
        NaryConstraint{ .names = &[_][]const u8{"bb"}, .constraint = &isEven },
        NaryConstraint{ .names = &[_][]const u8{"cc"}, .constraint = &isOdd },
    };

    const max_rounds = 20;

    const results = try solve(allocator, max_rounds, &variables, &constraints);
    std.debug.print("\n# RESULT:\n", .{});
    switch (results) {
        SolveResult.values => |x| {
            defer allocator.free(x);
            std.debug.print("success: {any}\n", .{x});
            for (x) |y| {
                std.debug.print("{s} = {d}\n", .{ y.name, y.value });
            }
        },
        SolveResult.conflicts => |x| {
            defer allocator.free(x);
            std.debug.print("failure: {any}\n", .{x});
            for (x) |y| {
                std.debug.print("{s} = {d} ({})\n", .{ y.name, y.value, y.conflict });
            }
        },
    }

    try testing.expect(1 == 1);
}

test "domain shuffle - length" {
    var domain = [_]i32{ 1, 2, 3, 4, 5, 6, 7, 8 };
    var v = Variable.init(.{ .name = "v", .domain = &domain });

    // Check length
    const lenBefore = v.domain().len;
    v.shuffleDomain();
    try testing.expect(v.domain().len == lenBefore);
}

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
