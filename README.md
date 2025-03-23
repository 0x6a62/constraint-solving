# constraint-solving

Constraint solving algorithms

# Components

* Modules
  * common - Common functions
  * ac3 - AC-3 solver
  * min-conflicts - Min Conflicts solver
  * back-tracking - Back-Tracking solver
* Example usage
  * example

# Development

Zig target version: 0.13.0

```
# Build
zig build

# Run
zig build run

# Test
zig build test --summary all
```

# Usage

## Install
```
zig fetch --save git+https://github.com/0x6a62/constraint-solving.git
```

## Add to your `build.zig`
```
const constraint_solving = b.dependency("constraint-solving", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("ac3", constraint_solving.module("ac3"));
exe.root_module.addImport("min-conflicts", constraint_solving.module("min-conflicts"));
exe.root_module.addImport("back-tracking", constraint_solving.module("back-tracking"));
```

## Using in code
```
# AC3
const ac3 = @import("ac3");
# Min Conflicts
const mc = @import("min-conflicts");
# Back Tracking
const bt = @import("back-tracking");
```

