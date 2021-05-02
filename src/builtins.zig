const std = @import("std");
const ArrayList = std.ArrayList;

const lib = @import("lib.zig");
usingnamespace lib;

//;

// TODO test that modifying a quotation works

// TODO make sure recursion works

// TODO specialized /i and /f ?

// TODO functions
// functional stuff
//   map fold curry compose
// math stuff
//   abs fract mod max min wrap clamp
// combinators from factor
//   cond 2dip 2keep
// string manipulation?
// type checking
//   float? int? etc

// TODO types
//   make sure accessing them from within zig is easy
//   map function for vecs vs protos should be specialized
//     vmap mmap
// vec
// maps/protos
// results

//;

pub fn f_panic(vm: *VM) EvalError!void {
    return error.Panic;
}

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

pub fn f_print_stack(vm: *VM) EvalError!void {
    std.debug.print("STACK| len: {}\n", .{vm.stack.data.items.len});
    for (vm.stack.data.items) |it, i| {
        std.debug.print("  {}| ", .{vm.stack.data.items.len - i - 1});
        vm.nicePrintValue(it);
        std.debug.print("\n", .{});
    }
}

pub fn f_print_top(vm: *VM) EvalError!void {
    std.debug.print("TOP| ", .{});
    vm.nicePrintValue(try vm.stack.peek());
    std.debug.print("\n", .{});
}

// math ===
// TODO these functions can be cleaned up somehow

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

pub fn f_lt(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    const a = try vm.stack.pop();
    switch (b) {
        .Int => |bi| switch (a) {
            .Int => |ai| {
                try vm.stack.push(.{ .Boolean = ai < bi });
            },
            .Float => |af| {
                try vm.stack.push(.{ .Boolean = af < @intToFloat(f32, bi) });
            },
            else => return error.TypeError,
        },
        .Float => |bf| switch (a) {
            .Int => |ai| {
                try vm.stack.push(.{ .Boolean = @intToFloat(f32, ai) < bf });
            },
            .Float => |af| {
                try vm.stack.push(.{ .Boolean = af < bf });
            },
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
            .Int => |ai| {
                try vm.stack.push(.{ .Boolean = ai <= bi });
            },
            .Float => |af| {
                try vm.stack.push(.{ .Boolean = af <= @intToFloat(f32, bi) });
            },
            else => return error.TypeError,
        },
        .Float => |bf| switch (a) {
            .Int => |ai| {
                try vm.stack.push(.{ .Boolean = @intToFloat(f32, ai) <= bf });
            },
            .Float => |af| {
                try vm.stack.push(.{ .Boolean = af <= bf });
            },
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
            .Int => |ai| {
                try vm.stack.push(.{ .Boolean = ai > bi });
            },
            .Float => |af| {
                try vm.stack.push(.{ .Boolean = af > @intToFloat(f32, bi) });
            },
            else => return error.TypeError,
        },
        .Float => |bf| switch (a) {
            .Int => |ai| {
                try vm.stack.push(.{ .Boolean = @intToFloat(f32, ai) > bf });
            },
            .Float => |af| {
                try vm.stack.push(.{ .Boolean = af > bf });
            },
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
            .Int => |ai| {
                try vm.stack.push(.{ .Boolean = ai >= bi });
            },
            .Float => |af| {
                try vm.stack.push(.{ .Boolean = af >= @intToFloat(f32, bi) });
            },
            else => return error.TypeError,
        },
        .Float => |bf| switch (a) {
            .Int => |ai| {
                try vm.stack.push(.{ .Boolean = @intToFloat(f32, ai) >= bf });
            },
            .Float => |af| {
                try vm.stack.push(.{ .Boolean = af >= bf });
            },
            else => return error.TypeError,
        },
        else => return error.TypeError,
    }
}

// conditionals ===

// TODO if_true and if_false should be quotations?
pub fn f_if(vm: *VM) EvalError!void {
    const if_false = try vm.stack.pop();
    const if_true = try vm.stack.pop();
    const condition = try vm.stack.pop();
    if (condition != .Boolean) return error.TypeError;
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
    try vm.stack.push(.{ .Boolean = vm.equalsValue(a, b) });
}

// TODO maybe make 'and' and 'or' work like lua
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

pub fn f_not(vm: *VM) EvalError!void {
    const b = try vm.stack.pop();
    if (b != .Boolean) return error.TypeError;
    try vm.stack.push(.{ .Boolean = !b.Boolean });
}

// shuffle ===

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
    try vm.stack.push(try vm.stack.index(1));
}

// combinators ===

pub fn f_dip(vm: *VM) EvalError!void {
    const quot = try vm.stack.pop();
    if (quot != .Quotation) return error.TypeError;
    const restore = try vm.stack.pop();
    try vm.eval(vm.quotation_table.items[quot.Quotation].get());
    try vm.stack.push(restore);
}

pub fn f_keep(vm: *VM) EvalError!void {
    const quot = try vm.stack.pop();
    if (quot != .Quotation) return error.TypeError;
    const restore = try vm.stack.peek();
    try vm.eval(vm.quotation_table.items[quot.Quotation].get());
    try vm.stack.push(restore);
}

pub fn f_bi(vm: *VM) EvalError!void {
    const q = try vm.stack.pop();
    if (q != .Quotation) return error.TypeError;
    const p = try vm.stack.pop();
    if (p != .Quotation) return error.TypeError;
    const x = try vm.stack.peek();
    try vm.eval(vm.quotation_table.items[p.Quotation].get());
    try vm.stack.push(x);
    try vm.eval(vm.quotation_table.items[q.Quotation].get());
}

pub fn f_2bi(vm: *VM) EvalError!void {
    const q = try vm.stack.pop();
    if (q != .Quotation) return error.TypeError;
    const p = try vm.stack.pop();
    if (p != .Quotation) return error.TypeError;
    const y = try vm.stack.peek();
    const x = try vm.stack.index(1);
    try vm.eval(vm.quotation_table.items[p.Quotation].get());
    try vm.stack.push(x);
    try vm.stack.push(y);
    try vm.eval(vm.quotation_table.items[q.Quotation].get());
}

pub fn f_tri(vm: *VM) EvalError!void {
    const r = try vm.stack.pop();
    if (r != .Quotation) return error.TypeError;
    const q = try vm.stack.pop();
    if (q != .Quotation) return error.TypeError;
    const p = try vm.stack.pop();
    if (p != .Quotation) return error.TypeError;
    const x = try vm.stack.peek();
    try vm.eval(vm.quotation_table.items[p.Quotation].get());
    try vm.stack.push(x);
    try vm.eval(vm.quotation_table.items[q.Quotation].get());
    try vm.stack.push(x);
    try vm.eval(vm.quotation_table.items[r.Quotation].get());
}

pub fn f_2tri(vm: *VM) EvalError!void {
    const r = try vm.stack.pop();
    if (r != .Quotation) return error.TypeError;
    const q = try vm.stack.pop();
    if (q != .Quotation) return error.TypeError;
    const p = try vm.stack.pop();
    if (p != .Quotation) return error.TypeError;
    const y = try vm.stack.peek();
    const x = try vm.stack.index(1);
    try vm.eval(vm.quotation_table.items[p.Quotation].get());
    try vm.stack.push(x);
    try vm.stack.push(y);
    try vm.eval(vm.quotation_table.items[q.Quotation].get());
    try vm.stack.push(x);
    try vm.stack.push(y);
    try vm.eval(vm.quotation_table.items[r.Quotation].get());
}

pub fn f_bi_star(vm: *VM) EvalError!void {
    const q = try vm.stack.pop();
    if (q != .Quotation) return error.TypeError;
    const p = try vm.stack.pop();
    if (p != .Quotation) return error.TypeError;
    const y = try vm.stack.pop();
    try vm.eval(vm.quotation_table.items[p.Quotation].get());
    try vm.stack.push(y);
    try vm.eval(vm.quotation_table.items[q.Quotation].get());
}

// TODO tri_star

pub fn f_bi_apply(vm: *VM) EvalError!void {
    const q = try vm.stack.pop();
    if (q != .Quotation) return error.TypeError;
    const restore = try vm.stack.pop();
    try vm.eval(vm.quotation_table.items[q.Quotation].get());
    try vm.stack.push(restore);
    try vm.eval(vm.quotation_table.items[q.Quotation].get());
}

pub fn f_tri_apply(vm: *VM) EvalError!void {
    const q = try vm.stack.pop();
    if (q != .Quotation) return error.TypeError;
    const a = try vm.stack.pop();
    const b = try vm.stack.pop();
    try vm.eval(vm.quotation_table.items[q.Quotation].get());
    try vm.stack.push(b);
    try vm.eval(vm.quotation_table.items[q.Quotation].get());
    try vm.stack.push(a);
    try vm.eval(vm.quotation_table.items[q.Quotation].get());
}

// vec ===

pub const Vec = struct {
    const Self = @This();

    pub const ft = ForeignTypeDef(Self, display, equals);

    data: ArrayList(Value),

    pub fn display(vm: *VM, p: ForeignPtr) void {
        const vec = p.cast(Self);
        std.debug.print("v[ ", .{});
        for (vec.data.items) |v| {
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
        var obj = try vm.allocator.create(Vec);
        obj.data = ArrayList(Value).init(vm.allocator);
        try vm.stack.push(Vec.ft.makePtr(obj));
    }

    pub fn _free(vm: *VM) EvalError!void {
        var ptr = try Vec.ft.assertValueIsType(try vm.stack.pop());
        ptr.data.deinit();
        vm.allocator.destroy(ptr);
    }

    pub fn _push(vm: *VM) EvalError!void {
        const val = try vm.stack.pop();
        var vec_ptr = try Vec.ft.assertValueIsType(try vm.stack.peek());
        try vec_ptr.data.append(val);
    }

    // TODO change order of args to vpush ct?
    // have it be   ( ... a b c d ct <vec> -- )
    pub fn _push_ct(vm: *VM) EvalError!void {
        // TODO assert stack size
        const ct_ = try vm.stack.pop();
        if (ct_ != .Int) return error.TypeError;

        // TODO ct has to be > 0
        const ct = @intCast(usize, ct_.Int);

        var vec_ptr = try Vec.ft.assertValueIsType(try vm.stack.index(ct));
        try vec_ptr.data.appendSlice(vm.stack.data.items[(vm.stack.data.items.len - ct)..vm.stack.data.items.len]);
        vm.stack.data.items.len -= ct;
    }

    pub fn _get(vm: *VM) EvalError!void {
        const idx = try vm.stack.pop();
        var vec_ptr = try Vec.ft.assertValueIsType(try vm.stack.pop());
        try vm.stack.push(vec_ptr.data.items[@intCast(usize, idx.Int)]);
    }
};

// map ===

// TODO mref vs mget
//  where mget should evaluate whatever it gets out of the map
//  and mref should just push it
// rename maps to 'prototypes' maybe because theyre supposed to be used for more than just hashtable stuff
pub const Map = struct {
    const Self = @This();

    const AutoHashMap = std.AutoHashMap;

    pub const ft = ForeignTypeDef(Self, display, null);

    map: AutoHashMap(usize, Value),

    pub fn _make(vm: *VM) EvalError!void {
        var obj = try vm.allocator.create(Self);
        obj.map = AutoHashMap(usize, Value).init(vm.allocator);
        try vm.stack.push(Self.ft.makePtr(obj));
    }

    pub fn _free(vm: *VM) EvalError!void {
        var ptr = try Self.ft.assertValueIsType(try vm.stack.pop());
        ptr.map.deinit();
        vm.allocator.destroy(ptr);
    }

    pub fn _set(vm: *VM) EvalError!void {
        var ptr = try Self.ft.assertValueIsType(try vm.stack.pop());
        const sym = try vm.stack.pop();
        if (sym != .Symbol) return error.TypeError;
        const value = try vm.stack.pop();
        // TODO handle override
        try ptr.map.put(sym.Symbol, value);
    }

    pub fn _get(vm: *VM) EvalError!void {
        var ptr = try Self.ft.assertValueIsType(try vm.stack.pop());
        const sym = try vm.stack.pop();
        if (sym != .Symbol) return error.TypeError;
        // TODO handle not found
        try vm.stack.push(ptr.map.get(sym.Symbol).?);
    }

    pub fn display(vm: *VM, p: ForeignPtr) void {
        const map = p.cast(Self);
        std.debug.print("m[ ", .{});
        var iter = map.map.iterator();
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
        .name = "if",
        .func = f_if,
    },
    .{
        .name = "eq?",
        .func = f_equal,
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
        .name = "not",
        .func = f_not,
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
        .name = "dip",
        .func = f_dip,
    },
    .{
        .name = "keep",
        .func = f_keep,
    },
    .{
        .name = "bi",
        .func = f_bi,
    },
    .{
        .name = "2bi",
        .func = f_2bi,
    },
    .{
        .name = "tri",
        .func = f_tri,
    },
    .{
        .name = "2tri",
        .func = f_2tri,
    },
    .{
        .name = "bi*",
        .func = f_bi_star,
    },
    .{
        .name = "bi^",
        .func = f_bi_apply,
    },
    .{
        .name = "tri^",
        .func = f_tri_apply,
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
        .name = "vpush!,ct",
        .func = Vec._push_ct,
    },
    .{
        .name = "vget",
        .func = Vec._get,
    },

    .{
        .name = "<map>",
        .func = Map._make,
    },
    .{
        .name = "<map>,free",
        .func = Map._free,
    },
    .{
        .name = "mget",
        .func = Map._get,
    },
    .{
        .name = "mset!",
        .func = Map._set,
    },
};
