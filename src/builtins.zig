const std = @import("std");
const ArrayList = std.ArrayList;

const lib = @import("lib.zig");
usingnamespace lib;

//;

// TODO need
// functions
//   functional stuff
//     map function for vecs vs protos should be specialized
//       vmap! mmap!
//     map fold
//     curry compose
//   math stuff
//     abs fract
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
//   type checking
//     float? int? etc

//;

pub fn f_panic(vm: *VM) EvalError!void {
    return error.Panic;
}

// TODO cant ude define word here because name is already interned
pub fn f_define(vm: *VM) EvalError!void {
    const name = try vm.stack.pop();
    if (name != .Symbol) return error.TypeError;
    const value = try vm.stack.pop();
    if (vm.word_table.items[name.Symbol]) |prev| {
        // TODO notify of overwrite
        vm.word_table.items[name.Symbol] = value;
    } else {
        vm.word_table.items[name.Symbol] = value;
    }
}

pub fn f_ref(vm: *VM) EvalError!void {
    const name = try vm.stack.pop();
    if (name != .Symbol) return error.TypeError;
    if (vm.word_table.items[name.Symbol]) |val| {
        try vm.stack.push(val);
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
    if (val != .Quotation and val != .ForeignFnPtr) return error.TypeError;
    try vm.evaluateValue(val);
}

pub fn f_clear_stack(vm: *VM) EvalError!void {
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
    switch (b) {
        .Int => |bi| switch (a) {
            .Int => |ai| try vm.stack.push(.{ .Int = ai + bi }),
            .Float => |af| try vm.stack.push(.{ .Float = af + @intToFloat(f32, bi) }),
            else => return error.TypeError,
        },
        .Float => |bf| switch (a) {
            .Int => |ai| try vm.stack.push(.{ .Float = @intToFloat(f32, ai) + bf }),
            .Float => |af| try vm.stack.push(.{ .Float = af + bf }),
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
            .Int => |ai| try vm.stack.push(.{ .Int = ai - bi }),
            .Float => |af| try vm.stack.push(.{ .Float = af - @intToFloat(f32, bi) }),
            else => return error.TypeError,
        },
        .Float => |bf| switch (a) {
            .Int => |ai| try vm.stack.push(.{ .Float = @intToFloat(f32, ai) - bf }),
            .Float => |af| try vm.stack.push(.{ .Float = af - bf }),
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
            .Int => |ai| try vm.stack.push(.{ .Int = ai * bi }),
            .Float => |af| try vm.stack.push(.{ .Float = af * @intToFloat(f32, bi) }),
            else => return error.TypeError,
        },
        .Float => |bf| switch (a) {
            .Int => |ai| try vm.stack.push(.{ .Float = @intToFloat(f32, ai) * bf }),
            .Float => |af| try vm.stack.push(.{ .Float = af * bf }),
            else => return error.TypeError,
        },
        else => return error.TypeError,
    }
}

pub fn f_divide(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    switch (b) {
        .Int => |bi| {
            if (bi == 0) return error.DivideByZero;
            switch (a) {
                .Int => |ai| try vm.stack.push(.{ .Int = @divTrunc(ai, bi) }),
                .Float => |af| try vm.stack.push(.{ .Float = af / @intToFloat(f32, bi) }),
                else => return error.TypeError,
            }
        },
        .Float => |bf| {
            if (bf == 0) return error.DivideByZero;
            switch (a) {
                .Int => |ai| try vm.stack.push(.{ .Float = @intToFloat(f32, ai) / bf }),
                .Float => |af| try vm.stack.push(.{ .Float = af / bf }),
                else => return error.TypeError,
            }
        },
        else => return error.TypeError,
    }
}

pub fn f_mod(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    switch (b) {
        .Int => |bi| {
            if (bi == 0) return error.DivideByZero;
            if (bi < 0) return error.NegativeDenominator;
            switch (a) {
                .Int => |ai| try vm.stack.push(.{ .Int = @mod(ai, bi) }),
                .Float => |af| try vm.stack.push(.{ .Float = @mod(af, @intToFloat(f32, bi)) }),
                else => return error.TypeError,
            }
        },
        .Float => |bf| {
            if (bf == 0) return error.DivideByZero;
            if (bf < 0) return error.NegativeDenominator;
            switch (a) {
                .Int => |ai| try vm.stack.push(.{ .Float = @mod(@intToFloat(f32, ai), bf) }),
                .Float => |af| try vm.stack.push(.{ .Float = @mod(af, bf) }),
                else => return error.TypeError,
            }
        },
        else => return error.TypeError,
    }
}

pub fn f_rem(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    switch (b) {
        .Int => |bi| {
            if (bi == 0) return error.DivideByZero;
            if (bi < 0) return error.NegativeDenominator;
            switch (a) {
                .Int => |ai| try vm.stack.push(.{ .Int = @rem(ai, bi) }),
                .Float => |af| try vm.stack.push(.{ .Float = @rem(af, @intToFloat(f32, bi)) }),
                else => return error.TypeError,
            }
        },
        .Float => |bf| {
            if (bf == 0) return error.DivideByZero;
            if (bf < 0) return error.NegativeDenominator;
            switch (a) {
                .Int => |ai| try vm.stack.push(.{ .Float = @rem(@intToFloat(f32, ai), bf) }),
                .Float => |af| try vm.stack.push(.{ .Float = @rem(af, bf) }),
                else => return error.TypeError,
            }
        },
        else => return error.TypeError,
    }
}

pub fn f_lt(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    switch (b) {
        .Int => |bi| switch (a) {
            .Int => |ai| try vm.stack.push(.{ .Boolean = ai < bi }),
            .Float => |af| try vm.stack.push(.{ .Boolean = af < @intToFloat(f32, bi) }),
            else => return error.TypeError,
        },
        .Float => |bf| switch (a) {
            .Int => |ai| try vm.stack.push(.{ .Boolean = @intToFloat(f32, ai) < bf }),
            .Float => |af| try vm.stack.push(.{ .Boolean = af < bf }),
            else => return error.TypeError,
        },
        else => return error.TypeError,
    }
}

pub fn f_lte(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    switch (b) {
        .Int => |bi| switch (a) {
            .Int => |ai| try vm.stack.push(.{ .Boolean = ai <= bi }),
            .Float => |af| try vm.stack.push(.{ .Boolean = af <= @intToFloat(f32, bi) }),
            else => return error.TypeError,
        },
        .Float => |bf| switch (a) {
            .Int => |ai| try vm.stack.push(.{ .Boolean = @intToFloat(f32, ai) <= bf }),
            .Float => |af| try vm.stack.push(.{ .Boolean = af <= bf }),
            else => return error.TypeError,
        },
        else => return error.TypeError,
    }
}

pub fn f_gt(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    switch (b) {
        .Int => |bi| switch (a) {
            .Int => |ai| try vm.stack.push(.{ .Boolean = ai > bi }),
            .Float => |af| try vm.stack.push(.{ .Boolean = af > @intToFloat(f32, bi) }),
            else => return error.TypeError,
        },
        .Float => |bf| switch (a) {
            .Int => |ai| try vm.stack.push(.{ .Boolean = @intToFloat(f32, ai) > bf }),
            .Float => |af| try vm.stack.push(.{ .Boolean = af > bf }),
            else => return error.TypeError,
        },
        else => return error.TypeError,
    }
}

pub fn f_gte(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    switch (b) {
        .Int => |bi| switch (a) {
            .Int => |ai| try vm.stack.push(.{ .Boolean = ai >= bi }),
            .Float => |af| try vm.stack.push(.{ .Boolean = af >= @intToFloat(f32, bi) }),
            else => return error.TypeError,
        },
        .Float => |bf| switch (a) {
            .Int => |ai| try vm.stack.push(.{ .Boolean = @intToFloat(f32, ai) >= bf }),
            .Float => |af| try vm.stack.push(.{ .Boolean = af >= bf }),
            else => return error.TypeError,
        },
        else => return error.TypeError,
    }
}

pub fn f_number_equal(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    switch (b) {
        .Int => |bi| switch (a) {
            .Int => |ai| try vm.stack.push(.{ .Boolean = ai == bi }),
            .Float => |af| try vm.stack.push(.{ .Boolean = af == @intToFloat(f32, bi) }),
            else => return error.TypeError,
        },
        .Float => |bf| switch (a) {
            .Int => |ai| try vm.stack.push(.{ .Boolean = @intToFloat(f32, ai) == bf }),
            .Float => |af| try vm.stack.push(.{ .Boolean = af == bf }),
            else => return error.TypeError,
        },
        else => return error.TypeError,
    }
}

// conditionals ===

pub fn f_choose(vm: *VM) EvalError!void {
    const if_false = try vm.stack.pop();
    const if_true = try vm.stack.pop();
    const condition = try vm.stack.pop();
    if (condition != .Boolean) return error.TypeError;
    switch (condition) {
        .Boolean => |b| {
            try vm.stack.push(if (b) if_true else if_false);
        },
        else => return error.TypeError,
    }
}

pub fn f_equal(vm: *VM) EvalError!void {
    const a = try vm.stack.pop();
    const b = try vm.stack.pop();
    const are_equal = if (@as(@TagType(Value), a) == b) switch (a) {
        .Int => |val| val == b.Int,
        .Float => |val| val == b.Float,
        .Boolean => |val| val == b.Boolean,
        .Sentinel => true,
        .Symbol => |val| val == b.Symbol,
        // TODO
        .String => false,
        .Quotation => false,
        .ForeignFnPtr => |ptr| ptr.name == b.ForeignFnPtr.name and
            ptr.func == b.ForeignFnPtr.func,
        .ForeignPtr => |ptr| ptr.ty == b.ForeignPtr.ty and
            vm.type_table.items[ptr.ty].equals_fn(vm, a.ForeignPtr, b.ForeignPtr),
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
    if (a != .Boolean) return error.TypeError;
    const b = try vm.stack.pop();
    if (b != .Boolean) return error.TypeError;
    try vm.stack.push(.{ .Boolean = a.Boolean and b.Boolean });
}

pub fn f_or(vm: *VM) EvalError!void {
    const a = try vm.stack.pop();
    if (a != .Boolean) return error.TypeError;
    const b = try vm.stack.pop();
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
    try vm.stack.push(try vm.return_stack.peek());
}

// shuffle ===

pub fn f_drop(vm: *VM) EvalError!void {
    _ = try vm.stack.pop();
}

pub fn f_dup(vm: *VM) EvalError!void {
    try vm.stack.push(try vm.stack.peek());
}

pub fn f_2dup(vm: *VM) EvalError!void {
    try vm.stack.push(try vm.stack.index(1));
    try vm.stack.push(try vm.stack.index(1));
}

pub fn f_3dup(vm: *VM) EvalError!void {
    try vm.stack.push(try vm.stack.index(2));
    try vm.stack.push(try vm.stack.index(2));
    try vm.stack.push(try vm.stack.index(2));
}

pub fn f_over(vm: *VM) EvalError!void {
    try vm.stack.push(try vm.stack.index(1));
}

pub fn f_2over(vm: *VM) EvalError!void {
    try vm.stack.push(try vm.stack.index(2));
    try vm.stack.push(try vm.stack.index(2));
}

pub fn f_pick(vm: *VM) EvalError!void {
    try vm.stack.push(try vm.stack.index(2));
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
    if (quot != .Quotation) return error.TypeError;
    const restore = try vm.stack.pop();
    try vm.eval(vm.quotation_table.items[quot.Quotation].get());
    try vm.stack.push(restore);
}

// vec ===

pub const Vec = struct {
    const Self = @This();

    pub const ft = ForeignTypeDef(ArrayList(Value), display, equals);

    pub fn display(vm: *VM, p: ForeignPtr) void {
        const vec = p.cast(ArrayList(Value));
        std.debug.print("v[ ", .{});
        for (vec.items) |v| {
            vm.nicePrintValue(v);
            std.debug.print(" ", .{});
        }
        std.debug.print("]", .{});
    }

    pub fn equals(vm: *VM, p1: ForeignPtr, p2: ForeignPtr) bool {
        // TODO
        return false;
    }

    //;

    pub fn _make(vm: *VM) EvalError!void {
        var obj = try vm.allocator.create(ArrayList(Value));
        obj.* = ArrayList(Value).init(vm.allocator);
        try vm.stack.push(Vec.ft.makePtr(obj));
    }

    pub fn _free(vm: *VM) EvalError!void {
        var ptr = try Vec.ft.assertValueIsType(try vm.stack.pop());
        ptr.deinit();
        vm.allocator.destroy(ptr);
    }

    pub fn _push(vm: *VM) EvalError!void {
        var vec_ptr = try Vec.ft.assertValueIsType(try vm.stack.pop());
        const val = try vm.stack.pop();
        try vec_ptr.append(val);
    }

    pub fn _get(vm: *VM) EvalError!void {
        var vec_ptr = try Vec.ft.assertValueIsType(try vm.stack.pop());
        const idx = try vm.stack.pop();
        try vm.stack.push(vec_ptr.items[@intCast(usize, idx.Int)]);
    }

    pub fn _len(vm: *VM) EvalError!void {
        var vec_ptr = try Vec.ft.assertValueIsType(try vm.stack.pop());
        try vm.stack.push(.{ .Int = @intCast(i32, vec_ptr.items.len) });
    }

    pub fn _reverse_in_place(vm: *VM) EvalError!void {
        var vec_ptr = try Vec.ft.assertValueIsType(try vm.stack.pop());
        std.mem.reverse(Value, vec_ptr.items);
    }
};

// map ===

// TODO
// mref vs mget
//   where mget should evaluate whatever it gets out of the map
//   and mref should just push it
// rename maps to 'prototypes' maybe because theyre supposed to be used for more than just hashtable stuff
// equals
pub const Proto = struct {
    const Self = @This();

    const Map = std.AutoHashMap(usize, Value);

    pub const ft = ForeignTypeDef(Map, display, null);

    pub fn _make(vm: *VM) EvalError!void {
        var obj = try vm.allocator.create(Map);
        obj.* = Map.init(vm.allocator);
        try vm.stack.push(Self.ft.makePtr(obj));
    }

    pub fn _free(vm: *VM) EvalError!void {
        var ptr = try Self.ft.assertValueIsType(try vm.stack.pop());
        ptr.deinit();
        vm.allocator.destroy(ptr);
    }

    pub fn _set(vm: *VM) EvalError!void {
        var ptr = try Self.ft.assertValueIsType(try vm.stack.pop());
        const sym = try vm.stack.pop();
        if (sym != .Symbol) return error.TypeError;
        const value = try vm.stack.pop();
        // TODO handle overwrite
        try ptr.put(sym.Symbol, value);
    }

    pub fn _get(vm: *VM) EvalError!void {
        var ptr = try Self.ft.assertValueIsType(try vm.stack.pop());
        const sym = try vm.stack.pop();
        if (sym != .Symbol) return error.TypeError;
        // TODO handle not found
        //        should probably return a result
        try vm.stack.push(ptr.get(sym.Symbol).?);
    }

    pub fn display(vm: *VM, p: ForeignPtr) void {
        const map = p.cast(Map);
        std.debug.print("m[ ", .{});
        var iter = map.iterator();
        while (iter.next()) |entry| {
            std.debug.print("{}: ", .{vm.symbol_table.items[entry.key]});
            vm.nicePrintValue(entry.value);
            std.debug.print(" ", .{});
        }
        std.debug.print("]", .{});
    }
};

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
        .func = Vec._make,
    },
    .{
        .name = "<vec>,free",
        .func = Vec._free,
    },
    .{
        .name = "vpush!",
        .func = Vec._push,
    },
    .{
        .name = "vget",
        .func = Vec._get,
    },
    .{
        .name = "vlen",
        .func = Vec._len,
    },
    .{
        .name = "vreverse!",
        .func = Vec._reverse_in_place,
    },

    .{
        .name = "<map>",
        .func = Proto._make,
    },
    .{
        .name = "<map>,free",
        .func = Proto._free,
    },
    .{
        .name = "mget",
        .func = Proto._get,
    },
    .{
        .name = "mset!",
        .func = Proto._set,
    },
};
