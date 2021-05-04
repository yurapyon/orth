const std = @import("std");
const ArrayList = std.ArrayList;

const lib = @import("lib.zig");
usingnamespace lib;

//;

// TODO need
// typecheck after you get all the args u want
// functions
//   functional stuff
//     map function for vecs vs protos should be specialized
//       vmap! mmap!
//     map fold
//     curry compose
//   math stuff
//     handle integer overflow
//     fract
//   type checking
//     float? int? etc
//   printing functions
//     display
//     write
// types
//   make sure accessing them from within zig is easy
//   results

// TODO want
// functions
//   bitwise operators
//   string manipulation

//;

pub fn f_panic(vm: *VM) EvalError!void {
    return error.Panic;
}

// TODO cant use defineWord here because name is already interned
pub fn f_define(vm: *VM) EvalError!void {
    const name = try vm.stack.pop();
    const value = try vm.stack.pop();
    if (name != .Symbol) return error.TypeError;

    if (vm.word_table.items[name.Symbol]) |prev| {
        // TODO notify of overwrite
        //  need to handle deleteing the value youre replacing
        vm.word_table.items[name.Symbol] = value;
    } else {
        vm.word_table.items[name.Symbol] = value;
    }
}

pub fn f_ref(vm: *VM) EvalError!void {
    const name = try vm.stack.pop();
    if (name != .Symbol) return error.TypeError;

    if (vm.word_table.items[name.Symbol]) |val| {
        try vm.stack.push(val.clone());
    } else {
        vm.error_info.word_not_found = vm.symbol_table.items[name.Symbol];
        return error.WordNotFound;
    }
}

pub fn f_define_local(vm: *VM) EvalError!void {
    const name = try vm.stack.pop();
    if (name != .Symbol) return error.TypeError;
    const value = try vm.stack.pop();
    if (false) {
        // TODO notify if name was used twice
    } else {
        try vm.locals.push(.{
            .name = name.Symbol,
            .value = value,
        });
    }
}

pub fn f_eval(vm: *VM) EvalError!void {
    const val = try vm.stack.pop();
    if (val != .Quotation and val != .FFI_Fn) return error.TypeError;
    try vm.evaluateValue(val);
}

pub fn f_clear_stack(vm: *VM) EvalError!void {
    // TODO handle rc
    vm.stack.data.items.len = 0;
}

pub fn f_print_top(vm: *VM) EvalError!void {
    std.debug.print("TOP| ", .{});
    vm.nicePrintValue(try vm.stack.peek());
    std.debug.print("\n", .{});
}

pub fn f_print_stack(vm: *VM) EvalError!void {
    std.debug.print("STACK| len: {}\n", .{vm.stack.data.items.len});
    for (vm.stack.data.items) |it, i| {
        std.debug.print("  {}| ", .{vm.stack.data.items.len - i - 1});
        vm.nicePrintValue(it);
        std.debug.print("\n", .{});
    }
}

// math ===

pub fn f_negative(vm: *VM) EvalError!void {
    const a = try vm.stack.pop();
    switch (a) {
        .Int => |i| try vm.stack.push(.{ .Int = -a.Int }),
        .Float => |f| try vm.stack.push(.{ .Float = -a.Float }),
        else => return error.TypeError,
    }
}

pub fn f_plus(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    if (@as(@TagType(Value), a) != b) return error.TypeError;
    switch (b) {
        .Int => |i| try vm.stack.push(.{ .Int = a.Int + i }),
        .Float => |f| try vm.stack.push(.{ .Float = a.Float + f }),
        else => return error.TypeError,
    }
}

pub fn f_minus(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    if (@as(@TagType(Value), a) != b) return error.TypeError;
    switch (b) {
        .Int => |i| try vm.stack.push(.{ .Int = a.Int - i }),
        .Float => |f| try vm.stack.push(.{ .Float = a.Float - f }),
        else => return error.TypeError,
    }
}

pub fn f_times(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    if (@as(@TagType(Value), a) != b) return error.TypeError;
    switch (b) {
        .Int => |i| try vm.stack.push(.{ .Int = a.Int * i }),
        .Float => |f| try vm.stack.push(.{ .Float = a.Float * f }),
        else => return error.TypeError,
    }
}

pub fn f_divide(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    if (@as(@TagType(Value), a) != b) return error.TypeError;
    switch (b) {
        .Int => |i| {
            if (i == 0) return error.DivideByZero;
            try vm.stack.push(.{ .Int = @divTrunc(a.Int, i) });
        },
        .Float => |f| {
            if (f == 0) return error.DivideByZero;
            try vm.stack.push(.{ .Float = a.Float / f });
        },
        else => return error.TypeError,
    }
}

pub fn f_mod(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    if (@as(@TagType(Value), a) != b) return error.TypeError;
    switch (b) {
        .Int => |i| {
            if (i == 0) return error.DivideByZero;
            if (i < 0) return error.NegativeDenominator;
            try vm.stack.push(.{ .Int = @mod(a.Int, i) });
        },
        .Float => |f| {
            if (f == 0) return error.DivideByZero;
            if (f < 0) return error.NegativeDenominator;
            try vm.stack.push(.{ .Float = @mod(a.Float, f) });
        },
        else => return error.TypeError,
    }
}

pub fn f_rem(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    if (@as(@TagType(Value), a) != b) return error.TypeError;
    switch (b) {
        .Int => |i| {
            if (i == 0) return error.DivideByZero;
            if (i < 0) return error.NegativeDenominator;
            try vm.stack.push(.{ .Int = @rem(a.Int, i) });
        },
        .Float => |f| {
            if (f == 0) return error.DivideByZero;
            if (f < 0) return error.NegativeDenominator;
            try vm.stack.push(.{ .Float = @rem(a.Float, f) });
        },
        else => return error.TypeError,
    }
}

pub fn f_lt(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    if (@as(@TagType(Value), a) != b) return error.TypeError;
    switch (b) {
        .Int => |i| try vm.stack.push(.{ .Boolean = a.Int < i }),
        .Float => |f| try vm.stack.push(.{ .Boolean = a.Float < f }),
        else => return error.TypeError,
    }
}

pub fn f_lte(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    if (@as(@TagType(Value), a) != b) return error.TypeError;
    switch (b) {
        .Int => |i| try vm.stack.push(.{ .Boolean = a.Int <= i }),
        .Float => |f| try vm.stack.push(.{ .Boolean = a.Float <= f }),
        else => return error.TypeError,
    }
}

pub fn f_gt(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    if (@as(@TagType(Value), a) != b) return error.TypeError;
    switch (b) {
        .Int => |i| try vm.stack.push(.{ .Boolean = a.Int > i }),
        .Float => |f| try vm.stack.push(.{ .Boolean = a.Float > f }),
        else => return error.TypeError,
    }
}

pub fn f_gte(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    if (@as(@TagType(Value), a) != b) return error.TypeError;
    switch (b) {
        .Int => |i| try vm.stack.push(.{ .Boolean = a.Int >= i }),
        .Float => |f| try vm.stack.push(.{ .Boolean = a.Float >= f }),
        else => return error.TypeError,
    }
}

pub fn f_number_equal(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    if (@as(@TagType(Value), a) != b) return error.TypeError;
    switch (b) {
        .Int => |i| try vm.stack.push(.{ .Boolean = a.Int == i }),
        .Float => |f| try vm.stack.push(.{ .Boolean = a.Float == f }),
        else => return error.TypeError,
    }
}

pub fn f_float_to_int(vm: *VM) EvalError!void {
    const a = try vm.stack.pop();
    if (a != .Float) return error.TypeError;
    try vm.stack.push(.{ .Int = @floatToInt(i32, a.Float) });
}

pub fn f_int_to_float(vm: *VM) EvalError!void {
    const a = try vm.stack.pop();
    if (a != .Int) return error.TypeError;
    try vm.stack.push(.{ .Float = @intToFloat(f32, a.Int) });
}

// conditionals ===

pub fn f_choose(vm: *VM) EvalError!void {
    const if_false = try vm.stack.pop();
    const if_true = try vm.stack.pop();
    const condition = try vm.stack.pop();
    if (condition != .Boolean) return error.TypeError;
    switch (condition) {
        .Boolean => |b| {
            if (b) {
                try vm.stack.push(if_true);
                if (if_false == .Ref) _ = if_false.Ref.rc.dec(vm);
            } else {
                try vm.stack.push(if_false);
                if (if_true == .Ref) _ = if_true.Ref.rc.dec(vm);
            }
        },
        else => return error.TypeError,
    }
}

pub fn f_equal(vm: *VM) EvalError!void {
    const a = try vm.stack.pop();
    const b = try vm.stack.pop();
    if (a == .Ref) _ = a.Ref.rc.dec(vm);
    if (b == .Ref) _ = b.Ref.rc.dec(vm);
    const are_equal = if (@as(@TagType(Value), a) == b) switch (a) {
        .Int => |val| val == b.Int,
        .Float => |val| val == b.Float,
        .Boolean => |val| val == b.Boolean,
        .Sentinel => true,
        .Symbol => |val| val == b.Symbol,
        // TODO
        .String => false,
        .Quotation => false,
        .FFI_Fn => |ptr| ptr.name == b.FFI_Fn.name and
            ptr.func == b.FFI_Fn.func,
        // TODO
        .Ref => false,
    } else false;
    try vm.stack.push(.{ .Boolean = are_equal });
}

pub fn f_not(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    if (b != .Boolean) return error.TypeError;
    try vm.stack.push(.{ .Boolean = !b.Boolean });
}

pub fn f_and(vm: *VM) EvalError!void {
    const a = try vm.stack.pop();
    const b = try vm.stack.pop();
    if (a != .Boolean) return error.TypeError;
    if (b != .Boolean) return error.TypeError;
    try vm.stack.push(.{ .Boolean = a.Boolean and b.Boolean });
}

pub fn f_or(vm: *VM) EvalError!void {
    const a = try vm.stack.pop();
    const b = try vm.stack.pop();
    if (a != .Boolean) return error.TypeError;
    if (b != .Boolean) return error.TypeError;
    try vm.stack.push(.{ .Boolean = a.Boolean or b.Boolean });
}

// return stack ===

pub fn f_to_r(vm: *VM) EvalError!void {
    try vm.return_stack.push(try vm.stack.pop());
}

pub fn f_from_r(vm: *VM) EvalError!void {
    try vm.stack.push(try vm.return_stack.pop());
}

pub fn f_peek_r(vm: *VM) EvalError!void {
    try vm.stack.push((try vm.return_stack.peek()).clone());
}

// shuffle ===

pub fn f_drop(vm: *VM) EvalError!void {
    const val = try vm.stack.pop();
    if (val == .Ref) _ = val.Ref.rc.dec(vm);
}

pub fn f_dup(vm: *VM) EvalError!void {
    const val = try vm.stack.peek();
    try vm.stack.push(val.clone());
}

pub fn f_2dup(vm: *VM) EvalError!void {
    const val = try vm.stack.peek();
    try vm.stack.push(val.clone());
    try vm.stack.push(val.clone());
}

pub fn f_3dup(vm: *VM) EvalError!void {
    const val = try vm.stack.peek();
    try vm.stack.push(val.clone());
    try vm.stack.push(val.clone());
    try vm.stack.push(val.clone());
}

pub fn f_over(vm: *VM) EvalError!void {
    const val = try vm.stack.index(1);
    try vm.stack.push(val.clone());
}

pub fn f_2over(vm: *VM) EvalError!void {
    const v1 = try vm.stack.index(1);
    const v2 = try vm.stack.index(2);
    try vm.stack.push(v2.clone());
    try vm.stack.push(v1.clone());
}

pub fn f_pick(vm: *VM) EvalError!void {
    const val = try vm.stack.index(2);
    try vm.stack.push(val.clone());
}

pub fn f_swap(vm: *VM) EvalError!void {
    var slice = vm.stack.data.items;
    if (slice.len < 2) return error.StackUnderflow;
    std.mem.swap(Value, &slice[slice.len - 1], &slice[slice.len - 2]);
}

pub fn f_rot(vm: *VM) EvalError!void {
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

// combinators ===

pub fn f_dip(vm: *VM) EvalError!void {
    const quot = try vm.stack.pop();
    const restore = try vm.stack.pop();
    if (quot != .Quotation) return error.TypeError;
    try vm.eval(vm.quotation_table.items[quot.Quotation].get());
    try vm.stack.push(restore);
}

// vec ===

pub const ft_vec = struct {
    const Self = @This();

    pub const ft = FFI_TypeDefinition(ArrayList(Value), display, equals, finalize);

    pub fn display(vm: *VM, rc: *FFI_Rc) void {
        const arr = rc.cast(ArrayList(Value));
        std.debug.print("v[ ", .{});
        for (arr.items) |v| {
            vm.nicePrintValue(v);
            std.debug.print(" ", .{});
        }
        std.debug.print("]", .{});
    }

    pub fn equals(vm: *VM, rc1: *FFI_Rc, rc2: *FFI_Rc) bool {
        // TODO
        return false;
    }

    pub fn finalize(vm: *VM, rc: *FFI_Rc) void {
        var arr = rc.cast(ArrayList(Value));
        for (arr.items) |val| {
            if (val == .Ref) {
                _ = val.Ref.rc.dec(vm);
            }
        }
        arr.deinit();
        vm.allocator.destroy(arr);
    }

    //;

    pub fn _make(vm: *VM) EvalError!void {
        var arr = try vm.allocator.create(ArrayList(Value));
        errdefer vm.allocator.destroy(arr);
        arr.* = ArrayList(Value).init(vm.allocator);

        var rc = try vm.allocator.create(FFI_Rc);
        rc.* = Self.ft.makeRc(arr);
        errdefer vm.allocator.destroy(rc);

        try vm.stack.push(.{ .Ref = rc.ref() });
    }

    pub fn _push(vm: *VM) EvalError!void {
        const ref = try vm.stack.pop();
        const val = try vm.stack.pop();
        try Self.ft.checkType(ref);

        if (!ref.Ref.rc.dec(vm)) return;

        var arr = ref.Ref.rc.cast(ArrayList(Value));
        try arr.append(val);
    }

    pub fn _get(vm: *VM) EvalError!void {
        const ref = try vm.stack.pop();
        const idx = try vm.stack.pop();
        try Self.ft.checkType(ref);
        if (idx != .Int) return error.TypeError;

        if (!ref.Ref.rc.dec(vm)) return;

        var arr = ref.Ref.rc.cast(ArrayList(Value));
        try vm.stack.push(arr.items[@intCast(usize, idx.Int)]);
    }

    pub fn _len(vm: *VM) EvalError!void {
        const ref = try vm.stack.pop();
        try Self.ft.checkType(ref);

        if (!ref.Ref.rc.dec(vm)) return;

        var arr = ref.Ref.rc.cast(ArrayList(Value));
        try vm.stack.push(.{ .Int = @intCast(i32, arr.items.len) });
    }

    pub fn _reverse_in_place(vm: *VM) EvalError!void {
        const ref = try vm.stack.pop();
        try Self.ft.checkType(ref);

        if (!ref.Ref.rc.dec(vm)) return;

        var arr = ref.Ref.rc.cast(ArrayList(Value));
        std.mem.reverse(Value, arr.items);
    }
};

// map ===

// TODO
// mref vs mget
//   where mget should evaluate whatever it gets out of the map
//   and mref should just push it
// rename maps to 'prototypes' maybe because theyre supposed to be used for more than just hashtable stuff
// equals
pub const ft_proto = struct {
    const Self = @This();

    const Map = std.AutoHashMap(usize, Value);

    pub const ft = FFI_TypeDefinition(Map, display, null, finalize);

    pub fn display(vm: *VM, rc: *FFI_Rc) void {
        const map = rc.cast(Map);
        std.debug.print("m[ ", .{});
        var iter = map.iterator();
        while (iter.next()) |entry| {
            std.debug.print("{}: ", .{vm.symbol_table.items[entry.key]});
            vm.nicePrintValue(entry.value);
            std.debug.print(" ", .{});
        }
        std.debug.print("]", .{});
    }

    pub fn finalize(vm: *VM, rc: *FFI_Rc) void {
        var map = rc.cast(Map);
        var iter = map.iterator();
        while (iter.next()) |entry| {
            var val = entry.value;
            if (val == .Ref) {
                _ = val.Ref.rc.dec(vm);
            }
        }
        map.deinit();
        vm.allocator.destroy(map);
    }

    //;

    pub fn _make(vm: *VM) EvalError!void {
        var map = try vm.allocator.create(Map);
        errdefer vm.allocator.destroy(map);
        map.* = Map.init(vm.allocator);

        var rc = try vm.allocator.create(FFI_Rc);
        rc.* = Self.ft.makeRc(map);
        errdefer vm.allocator.destroy(rc);

        try vm.stack.push(.{ .Ref = rc.ref() });
    }

    pub fn _set(vm: *VM) EvalError!void {
        const ref = try vm.stack.pop();
        const sym = try vm.stack.pop();
        const value = try vm.stack.pop();
        try Self.ft.checkType(ref);
        if (sym != .Symbol) return error.TypeError;

        if (!ref.Ref.rc.dec(vm)) return;

        var map = ref.Ref.rc.cast(Map);

        // TODO handle overwrite
        try map.put(sym.Symbol, value);
    }

    pub fn _get(vm: *VM) EvalError!void {
        const ref = try vm.stack.pop();
        const sym = try vm.stack.pop();
        try Self.ft.checkType(ref);
        if (sym != .Symbol) return error.TypeError;

        if (!ref.Ref.rc.dec(vm)) return;

        var map = ref.Ref.rc.cast(Map);

        if (map.get(sym.Symbol)) |val| {
            try vm.stack.push(val.clone());
            try vm.stack.push(.{ .Boolean = true });
        } else {
            try vm.stack.push(.{ .Boolean = false });
            try vm.stack.push(.{ .Boolean = false });
        }
    }
};

// =====

pub const builtins = [_]struct {
    name: []const u8,
    func: FFI_Fn.Function,
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
        .name = "@local",
        .func = f_define_local,
    },
    .{
        .name = "eval",
        .func = f_eval,
    },
    .{
        .name = "clear-stack",
        .func = f_clear_stack,
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
        .name = "neg",
        .func = f_negative,
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
        .name = "mod",
        .func = f_mod,
    },
    .{
        .name = "rem",
        .func = f_rem,
    },
    .{
        .name = "<",
        .func = f_lt,
    },
    .{
        .name = "<=",
        .func = f_lte,
    },
    .{
        .name = ">",
        .func = f_gt,
    },
    .{
        .name = ">=",
        .func = f_gte,
    },
    .{
        .name = "=",
        .func = f_number_equal,
    },
    .{
        .name = "float>int",
        .func = f_float_to_int,
    },
    .{
        .name = "int>float",
        .func = f_int_to_float,
    },

    .{
        .name = "?",
        .func = f_choose,
    },
    .{
        .name = "eq?",
        .func = f_equal,
    },
    .{
        .name = "not",
        .func = f_not,
    },
    .{
        .name = "and",
        .func = f_and,
    },
    .{
        .name = "or",
        .func = f_or,
    },

    .{
        .name = ">R",
        .func = f_to_r,
    },
    .{
        .name = "<R",
        .func = f_from_r,
    },
    .{
        .name = ".R",
        .func = f_peek_r,
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
        .name = "2dup",
        .func = f_2dup,
    },
    .{
        .name = "3dup",
        .func = f_3dup,
    },
    .{
        .name = "over",
        .func = f_over,
    },
    .{
        .name = "2over",
        .func = f_2over,
    },
    .{
        .name = "pick",
        .func = f_pick,
    },
    .{
        .name = "swap",
        .func = f_swap,
    },
    .{
        .name = "rot<",
        .func = f_rot,
    },
    .{
        .name = "rot>",
        .func = f_neg_rot,
    },

    .{
        .name = "dip",
        .func = f_dip,
    },

    .{
        .name = "<vec>",
        .func = ft_vec._make,
    },
    .{
        .name = "vpush!",
        .func = ft_vec._push,
    },
    .{
        .name = "vget",
        .func = ft_vec._get,
    },
    .{
        .name = "vlen",
        .func = ft_vec._len,
    },
    .{
        .name = "vreverse!",
        .func = ft_vec._reverse_in_place,
    },

    .{
        .name = "<map>",
        .func = ft_proto._make,
    },
    .{
        .name = "mget*",
        .func = ft_proto._get,
    },
    .{
        .name = "mset!",
        .func = ft_proto._set,
    },
};
