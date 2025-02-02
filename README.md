# constraint-solving

Constraint solving algorithms

# Components

* Modules
  * ac3 - AC-3 solver
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
```

## Using in code
```
const ac3 = @import("ac3");
```

