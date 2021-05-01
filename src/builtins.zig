const std = @import("std");
const ArrayList = std.ArrayList;

const lib = @import("lib.zig");
usingnamespace lib;

//;

// map fold, etc

//;

const ValTag = @TagType(Value);

//;

pub fn f_panic(vm: *VM) EvalError!void {
    return error.Panic;
}

pub fn f_define(vm: *VM) EvalError!void {
    const name = try vm.stack.pop();
    try name.assertType(&[_]ValTag{.Symbol});
    const value = try vm.stack.pop();
    if (vm.word_table.items[name.Symbol]) |prev| {
        // notify of overwrite
    } else {
        vm.word_table.items[name.Symbol] = value;
    }
}

pub fn f_ref(vm: *VM) EvalError!void {
    const name = try vm.stack.pop();
    try name.assertType(&[_]ValTag{.Symbol});
    if (vm.word_table.items[name.Symbol]) |val| {
        try vm.stack.push(val);
    } else {
        lib.error_info.word_not_found = vm.string_table.items[name.Symbol];
        return error.WordNotFound;
    }
}

pub fn f_eval(vm: *VM) EvalError!void {
    const val = try vm.stack.pop();
    try val.assertType(&[_]ValTag{
        .ForeignFnPtr,
        .Quotation,
    });
    try vm.evaluateValue(val);
}

pub fn f_print_stack(vm: *VM) EvalError!void {
    std.debug.print("STACK| len: {}\n", .{vm.stack.data.items.len});
    for (vm.stack.data.items) |it, i| {
        std.debug.print("  {}| ", .{vm.stack.data.items.len - i - 1});
        it.nicePrint(vm);
        std.debug.print("\n", .{});
    }
}

pub fn f_print_top(vm: *VM) EvalError!void {
    std.debug.print("TOP| ", .{});
    (try vm.stack.peek()).nicePrint(vm);
    std.debug.print("\n", .{});
}

pub fn f_plus(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    switch (b) {
        .Int => |bi| switch (a) {
            .Int => |ai| {
                try vm.stack.push(.{ .Int = ai + bi });
            },
            .Float => |af| {
                try vm.stack.push(.{ .Float = af + @intToFloat(f32, bi) });
            },
            else => return error.TypeError,
        },
        .Float => |bf| switch (a) {
            .Int => |ai| {
                try vm.stack.push(.{ .Float = @intToFloat(f32, ai) + bf });
            },
            .Float => |af| {
                try vm.stack.push(.{ .Float = af + bf });
            },
            else => return error.TypeError,
        },
        else => return error.TypeError,
    }
}

pub fn f_minus(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    switch (b) {
        .Int => |bi| switch (a) {
            .Int => |ai| {
                try vm.stack.push(.{ .Int = ai - bi });
            },
            .Float => |af| {
                try vm.stack.push(.{ .Float = af - @intToFloat(f32, bi) });
            },
            else => return error.TypeError,
        },
        .Float => |bf| switch (a) {
            .Int => |ai| {
                try vm.stack.push(.{ .Float = @intToFloat(f32, ai) - bf });
            },
            .Float => |af| {
                try vm.stack.push(.{ .Float = af - bf });
            },
            else => return error.TypeError,
        },
        else => return error.TypeError,
    }
}

pub fn f_times(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    switch (b) {
        .Int => |bi| switch (a) {
            .Int => |ai| {
                try vm.stack.push(.{ .Int = ai * bi });
            },
            .Float => |af| {
                try vm.stack.push(.{ .Float = af * @intToFloat(f32, bi) });
            },
            else => return error.TypeError,
        },
        .Float => |bf| switch (a) {
            .Int => |ai| {
                try vm.stack.push(.{ .Float = @intToFloat(f32, ai) * bf });
            },
            .Float => |af| {
                try vm.stack.push(.{ .Float = af * bf });
            },
            else => return error.TypeError,
        },
        else => return error.TypeError,
    }
}

pub fn f_divide(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    switch (b) {
        .Int => |bi| switch (a) {
            .Int => |ai| {
                // TODO use divFloor?
                try vm.stack.push(.{ .Int = @divFloor(ai, bi) });
            },
            .Float => |af| {
                try vm.stack.push(.{ .Float = af / @intToFloat(f32, bi) });
            },
            else => return error.TypeError,
        },
        .Float => |bf| switch (a) {
            .Int => |ai| {
                try vm.stack.push(.{ .Float = @intToFloat(f32, ai) / bf });
            },
            .Float => |af| {
                try vm.stack.push(.{ .Float = af / bf });
            },
            else => return error.TypeError,
        },
        else => return error.TypeError,
    }
}

pub fn f_if(vm: *VM) EvalError!void {
    const condition = try vm.stack.pop();
    try condition.assertType(&[_]ValTag{.Boolean});
    const if_false = try vm.stack.pop();
    const if_true = try vm.stack.pop();
    switch (condition) {
        .Boolean => |bl| {
            if (bl) {
                try vm.evaluateValue(if_true);
            } else {
                try vm.evaluateValue(if_false);
            }
        },
        else => return error.TypeError,
    }
}

pub fn f_equal(vm: *VM) EvalError!void {
    const a = try vm.stack.pop();
    const b = try vm.stack.pop();
    try vm.stack.push(.{ .Boolean = a.equals(vm, b) });
}

// stack manipulation ==

pub fn f_drop(vm: *VM) EvalError!void {
    _ = try vm.stack.pop();
}

pub fn f_dup(vm: *VM) EvalError!void {
    try vm.stack.push(try vm.stack.peek());
}

pub fn f_swap(vm: *VM) EvalError!void {
    const a = try vm.stack.pop();
    const b = try vm.stack.pop();
    try vm.stack.push(a);
    try vm.stack.push(b);
}

pub fn f_rot(vm: *VM) EvalError!void {
    // TODO can optimize this
    const z = try vm.stack.pop();
    const y = try vm.stack.pop();
    const x = try vm.stack.pop();
    try vm.stack.push(y);
    try vm.stack.push(z);
    try vm.stack.push(x);
}

pub fn f_neg_rot(vm: *VM) EvalError!void {
    const z = try vm.stack.pop();
    const y = try vm.stack.pop();
    const x = try vm.stack.pop();
    try vm.stack.push(z);
    try vm.stack.push(x);
    try vm.stack.push(y);
}

pub fn f_over(vm: *VM) EvalError!void {
    try vm.stack.push((try vm.stack.index(1)).*);
}

// vec ===

pub const Vec = struct {
    const Self = @This();

    pub const ft = ForeignType.genHelper(Self, display, equals);

    data: ArrayList(Value),

    pub fn display(vm: *VM, p: ForeignPtr) void {
        const vec = p.cast(Self);
        std.debug.print("v[ ", .{});
        for (vec.data.items) |v| {
            v.nicePrint(vm);
            std.debug.print(" ", .{});
        }
        std.debug.print("]", .{});
    }

    pub fn equals(vm: *VM, p1: ForeignPtr, p2: ForeignPtr) bool {
        return false;
    }
};

pub fn f_make_vec(vm: *VM) EvalError!void {
    var obj = try vm.allocator.create(Vec);
    obj.data = ArrayList(Value).init(vm.allocator);
    try vm.stack.push(Vec.ft.make(obj));
}

pub fn f_vec_free(vm: *VM) EvalError!void {
    var ptr = try Vec.ft.assertValueIsType(try vm.stack.pop());
    ptr.data.deinit();
    vm.allocator.destroy(ptr);
}

pub fn f_vec_push(vm: *VM) EvalError!void {
    const val = try vm.stack.pop();
    var vec_ptr = try Vec.ft.assertValueIsType(try vm.stack.peek());
    try vec_ptr.data.append(val);
}

pub fn f_vec_push_ct(vm: *VM) EvalError!void {
    // TODO assert stack size
    const ct_ = try vm.stack.pop();
    try ct_.assertType(&[_]ValTag{.Int});

    // TODO ct has to be > 0
    const ct = @intCast(usize, ct_.Int);

    var vec_ptr = try Vec.ft.assertValueIsType((try vm.stack.index(ct)).*);
    try vec_ptr.data.appendSlice(vm.stack.data.items[(vm.stack.data.items.len - ct)..vm.stack.data.items.len]);
    vm.stack.data.items.len -= ct;
}

pub fn f_vec_get(vm: *VM) EvalError!void {
    const idx = try vm.stack.pop();
    var vec_ptr = try Vec.ft.assertValueIsType(try vm.stack.pop());
    try vm.stack.push(vec_ptr.data.items[@intCast(usize, idx.Int)]);
}

// =====

pub const builtins = [_]struct {
    name: []const u8,
    func: ForeignFn,
}{
    .{
        .name = "panic",
        .func = f_panic,
    },
    .{
        .name = "@",
        .func = f_define,
    },
    .{
        .name = "ref",
        .func = f_ref,
    },
    .{
        .name = "eval",
        .func = f_eval,
    },
    .{
        .name = ".",
        .func = f_print_top,
    },
    .{
        .name = ".stack",
        .func = f_print_stack,
    },
    .{
        .name = "+",
        .func = f_plus,
    },
    .{
        .name = "-",
        .func = f_minus,
    },
    .{
        .name = "*",
        .func = f_times,
    },
    .{
        .name = "/",
        .func = f_divide,
    },
    .{
        .name = "if",
        .func = f_if,
    },
    .{
        .name = "eq?",
        .func = f_equal,
    },

    .{
        .name = "drop",
        .func = f_drop,
    },
    .{
        .name = "dup",
        .func = f_dup,
    },
    .{
        .name = "swap",
        .func = f_swap,
    },
    .{
        .name = "rot",
        .func = f_rot,
    },
    .{
        .name = "-rot",
        .func = f_neg_rot,
    },
    .{
        .name = "over",
        .func = f_over,
    },

    .{
        .name = "<vec>",
        .func = f_make_vec,
    },
    .{
        .name = "vec-free",
        .func = f_make_vec,
    },
    .{
        .name = "vpush!",
        .func = f_vec_push,
    },
    .{
        .name = "vpush!,ct",
        .func = f_vec_push_ct,
    },
    .{
        .name = "vget",
        .func = f_vec_get,
    },
};
