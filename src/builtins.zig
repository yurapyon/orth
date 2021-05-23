const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const lib = @import("lib.zig");
usingnamespace lib;

//;

// typecheck after you get all the args u want

// display is human readable
// write is machine readable

// slices generated can be interned from vectors
//   like the relationship between sumbols and strings

//;

// just use a number type instead of ints and floats?
//   gets around type checking for math fns
//   makes bitwise operators weird

// if i want to use the return stack for eval,restore
//   eval,restore needs to pop the values when called, cant put them on the rstack before

// TODO need
// ports
//   displayp writep
//   string, file, stdin/err/out, vector port
//   write an iterator to a port
// all returns of error.TypeError report what was expected
// functions
//   text
//     string manipulation
//     string format
//     printing functions
//       write
//         need to translate '\n' in strings to a "\n"
//   thread exit
//   math stuff
//     handle integer overflow
//       check where it can happen and make it a Thread.Error or change + to +%
// types
//   make sure accessing them from within zig is easy
// short circuiting and and or
// more ways to print vm info
//   word table
// subslice, first rest
// map, weak ptrs

// TODO want
// functions
//   math
//     fract
//     dont type check, have separte functions for ints and floats ?
//       general versions of fns like + can be written in orth that typecheck
// homogeneous vector thing
//   []i64, []f64 etc

//;

pub fn f_panic(t: *Thread) Thread.Error!void {
    return error.Panic;
}

pub fn f_define(t: *Thread) Thread.Error!void {
    const name = try t.stack.pop();
    const value = try t.stack.pop();
    if (name != .Symbol) return error.TypeError;

    if (t.vm.word_table.items[name.Symbol]) |prev| {
        // TODO print that youre overriding?
        // t.vm.dropValue(prev);
    }
    // t.vm.word_table.items[name.Symbol] = value;
}

pub fn f_def(t: *Thread) Thread.Error!void {
    const eval_on_lookup = try t.stack.pop();
    const name = try t.stack.pop();
    const value = try t.stack.pop();
    if (name != .Symbol) return error.TypeError;
    if (eval_on_lookup != .Boolean) return error.TypeError;

    if (t.vm.word_table.items[name.Symbol]) |prev| {
        // TODO print that youre overriding?
        t.vm.dropValue(prev.value);
    }
    t.vm.word_table.items[name.Symbol] = .{
        .value = value,
        .eval_on_lookup = eval_on_lookup.Boolean,
    };
}

pub fn f_ref(t: *Thread) Thread.Error!void {
    const name = try t.stack.pop();
    if (name != .Symbol) return error.TypeError;

    if (t.vm.word_table.items[name.Symbol]) |dword| {
        try t.stack.push(t.vm.dupValue(dword.value));
        try t.stack.push(.{ .Boolean = true });
    } else {
        try t.stack.push(.{ .Boolean = false });
        try t.stack.push(.{ .Boolean = false });
    }
}

pub fn f_eval(t: *Thread) Thread.Error!void {
    const val = try t.stack.pop();
    try t.evaluateValue(val, 0);
}

pub fn f_eval_restore(t: *Thread) Thread.Error!void {
    const restore_num = try t.stack.pop();
    const val = try t.stack.pop();
    if (restore_num != .Int) return error.TypeError;
    try t.evaluateValue(val, @intCast(usize, restore_num.Int));
}

pub fn f_push_restore(t: *Thread) Thread.Error!void {
    const val = try t.stack.pop();
    try t.restore_stack.push(val);
}

pub fn f_stack_len(t: *Thread) Thread.Error!void {
    try t.stack.push(.{ .Int = @intCast(i64, t.stack.data.items.len) });
}

pub fn f_stack_index(t: *Thread) Thread.Error!void {
    const idx = try t.stack.pop();
    if (idx != .Int) return error.TypeError;
    try t.stack.push(t.vm.dupValue((try t.stack.index(@intCast(usize, idx.Int))).*));
}

pub fn f_clear_stack(t: *Thread) Thread.Error!void {
    for (t.stack.data.items) |v| {
        t.vm.dropValue(v);
    }
    t.stack.data.items.len = 0;
}

pub fn f_print_stack(t: *Thread) Thread.Error!void {
    const len = t.stack.data.items.len;
    std.debug.print("STACK| len: {}\n", .{len});
    for (t.stack.data.items) |it, i| {
        std.debug.print("  {}| ", .{len - i - 1});
        t.nicePrintValue(it);
        std.debug.print("\n", .{});
    }
}

pub fn f_print_rstack(t: *Thread) Thread.Error!void {
    const len = t.return_stack.data.items.len;
    std.debug.print("RSTACK| len: {}\n", .{len});
    for (t.return_stack.data.items) |it, i| {
        std.debug.print("  {}| ", .{len - i - 1});
        t.nicePrintValue(it.value);
        if (it.restore_ct == std.math.maxInt(usize)) {
            std.debug.print(" :: max\n", .{});
        } else {
            std.debug.print(" :: {}\n", .{it.restore_ct});
        }
    }
}

pub fn f_print_current(t: *Thread) Thread.Error!void {
    std.debug.print("CURRENT EXEC: {}| {{", .{t.restore_ct});
    for (t.current_execution) |val| {
        t.nicePrintValue(val);
    }
    std.debug.print("}}\n", .{});
}

// display/write ===

fn displayValue(t: *Thread, value: Value) void {
    switch (value) {
        .Int => |val| std.debug.print("{}", .{val}),
        .Float => |val| std.debug.print("{d}f", .{val}),
        .Char => |val| switch (val) {
            ' ' => std.debug.print("#\\space", .{}),
            '\n' => std.debug.print("#\\newline", .{}),
            '\t' => std.debug.print("#\\tab", .{}),
            else => std.debug.print("#\\{c}", .{val}),
        },
        .Boolean => |val| {
            const str = if (val) "#t" else "#f";
            std.debug.print("{s}", .{str});
        },
        .Sentinel => std.debug.print("#sentinel", .{}),
        .Symbol => |val| std.debug.print(":{}", .{t.vm.symbol_table.items[val]}),
        .Word => |val| std.debug.print("{}", .{t.vm.symbol_table.items[val]}),
        .String => |val| std.debug.print("{}", .{val}),
        .Slice => |slc| {
            std.debug.print("{{ ", .{});
            for (slc) |val| {
                displayValue(t, val);
                std.debug.print(" ", .{});
            }
            std.debug.print("}}", .{});
        },
        .FFI_Fn => |val| std.debug.print("fn({})", .{t.vm.symbol_table.items[val.name]}),
        .FFI_Ptr => |ptr| t.vm.type_table.items[ptr.type_id].ty.FFI.display_fn(t, ptr),
    }
}

pub fn f_display(t: *Thread) Thread.Error!void {
    const val = try t.stack.pop();
    displayValue(t, val);
    t.vm.dropValue(val);
}

// repl ==

pub fn f_read(t: *Thread) Thread.Error!void {
    const stdin = std.io.getStdIn();
    // TODO report errors better
    const str: ?[]u8 = stdin.reader().readUntilDelimiterAlloc(t.vm.allocator, '\n', 2048) catch null;
    if (str) |s| {
        try t.vm.string_literals.append(s);
        try t.stack.push(.{ .String = s });
    }
}

// TODO this should return a result
pub fn f_parse(t: *Thread) Thread.Error!void {
    const str = try t.stack.pop();
    if (str != .String) return error.TypeError;

    var tk = Tokenizer.init(str.String);
    var tokens = ArrayList(Token).init(t.vm.allocator);
    defer tokens.deinit();

    // TODO report errors better
    //  errors like this should make it into orth
    while (tk.next() catch unreachable) |token| {
        try tokens.append(token);
    }

    const vals = t.vm.parse(tokens.items) catch unreachable;
    defer t.vm.allocator.free(vals);

    // TODO
    // var rc = try ft_quotation.makeRc(t.vm.allocator);
    // try rc.obj.appendSlice(vals);
    // try t.evaluateValue(.{ .FFI_Ptr = ft_quotation.ffi_type.makePtr(rc.ref()) }, 0);
}

// built in types ===

pub fn f_value_type_of(t: *Thread) Thread.Error!void {
    const val = try t.stack.pop();
    try t.stack.push(.{ .Symbol = @enumToInt(@as(ValueType, val)) });
    t.vm.dropValue(val);
}

pub fn f_ffi_type_of(t: *Thread) Thread.Error!void {
    const val = try t.stack.pop();
    if (val != .FFI_Ptr) return error.TypeError;
    try t.stack.push(.{ .Symbol = t.vm.type_table.items[val.FFI_Ptr.type_id].name_id });
    t.vm.dropValue(val);
}

pub fn f_word_to_symbol(t: *Thread) Thread.Error!void {
    const word = try t.stack.pop();
    if (word != .Word) return error.TypeError;
    try t.stack.push(.{ .Symbol = word.Word });
}

pub fn f_symbol_to_word(t: *Thread) Thread.Error!void {
    const sym = try t.stack.pop();
    if (sym != .Symbol) return error.TypeError;
    try t.stack.push(.{ .Word = sym.Symbol });
}

pub fn f_symbol_to_string(t: *Thread) Thread.Error!void {
    const sym = try t.stack.pop();
    if (sym != .Symbol) return error.TypeError;
    try t.stack.push(.{ .String = t.vm.symbol_table.items[sym.Symbol] });
}

// chars ===

// TODO
// pub fn f_char_to_integer()

// math ===

pub fn f_negative(t: *Thread) Thread.Error!void {
    const val = try t.stack.pop();
    switch (val) {
        .Int => |i| try t.stack.push(.{ .Int = -i }),
        .Float => |f| try t.stack.push(.{ .Float = -f }),
        else => return error.TypeError,
    }
}

pub fn f_plus(t: *Thread) Thread.Error!void {
    const b = try t.stack.pop();
    const a = try t.stack.pop();
    if (@as(@TagType(Value), a) != b) return error.TypeError;
    switch (b) {
        .Int => |i| try t.stack.push(.{ .Int = a.Int + i }),
        .Float => |f| try t.stack.push(.{ .Float = a.Float + f }),
        else => return error.TypeError,
    }
}

pub fn f_minus(t: *Thread) Thread.Error!void {
    const b = try t.stack.pop();
    const a = try t.stack.pop();
    if (@as(@TagType(Value), a) != b) return error.TypeError;
    switch (b) {
        .Int => |i| try t.stack.push(.{ .Int = a.Int - i }),
        .Float => |f| try t.stack.push(.{ .Float = a.Float - f }),
        else => return error.TypeError,
    }
}

pub fn f_times(t: *Thread) Thread.Error!void {
    const b = try t.stack.pop();
    const a = try t.stack.pop();
    if (@as(@TagType(Value), a) != b) return error.TypeError;
    switch (b) {
        .Int => |i| try t.stack.push(.{ .Int = a.Int * i }),
        .Float => |f| try t.stack.push(.{ .Float = a.Float * f }),
        else => return error.TypeError,
    }
}

pub fn f_divide(t: *Thread) Thread.Error!void {
    const b = try t.stack.pop();
    const a = try t.stack.pop();
    if (@as(@TagType(Value), a) != b) return error.TypeError;
    switch (b) {
        .Int => |i| {
            if (i == 0) return error.DivideByZero;
            try t.stack.push(.{ .Int = @divTrunc(a.Int, i) });
        },
        .Float => |f| {
            if (f == 0) return error.DivideByZero;
            try t.stack.push(.{ .Float = a.Float / f });
        },
        else => return error.TypeError,
    }
}

pub fn f_mod(t: *Thread) Thread.Error!void {
    const b = try t.stack.pop();
    const a = try t.stack.pop();
    if (@as(@TagType(Value), a) != b) return error.TypeError;
    switch (b) {
        .Int => |i| {
            if (i == 0) return error.DivideByZero;
            if (i < 0) return error.NegativeDenominator;
            try t.stack.push(.{ .Int = @mod(a.Int, i) });
        },
        .Float => |f| {
            if (f == 0) return error.DivideByZero;
            if (f < 0) return error.NegativeDenominator;
            try t.stack.push(.{ .Float = @mod(a.Float, f) });
        },
        else => return error.TypeError,
    }
}

pub fn f_rem(t: *Thread) Thread.Error!void {
    const b = try t.stack.pop();
    const a = try t.stack.pop();
    if (@as(@TagType(Value), a) != b) return error.TypeError;
    switch (b) {
        .Int => |i| {
            if (i == 0) return error.DivideByZero;
            if (i < 0) return error.NegativeDenominator;
            try t.stack.push(.{ .Int = @rem(a.Int, i) });
        },
        .Float => |f| {
            if (f == 0) return error.DivideByZero;
            if (f < 0) return error.NegativeDenominator;
            try t.stack.push(.{ .Float = @rem(a.Float, f) });
        },
        else => return error.TypeError,
    }
}

pub fn f_lt(t: *Thread) Thread.Error!void {
    const b = try t.stack.pop();
    const a = try t.stack.pop();
    if (@as(@TagType(Value), a) != b) return error.TypeError;
    switch (b) {
        .Int => |i| try t.stack.push(.{ .Boolean = a.Int < i }),
        .Float => |f| try t.stack.push(.{ .Boolean = a.Float < f }),
        else => return error.TypeError,
    }
}

pub fn f_number_equal(t: *Thread) Thread.Error!void {
    const b = try t.stack.pop();
    const a = try t.stack.pop();
    if (@as(@TagType(Value), a) != b) return error.TypeError;
    switch (b) {
        .Int => |i| try t.stack.push(.{ .Boolean = a.Int == i }),
        .Float => |f| try t.stack.push(.{ .Boolean = a.Float == f }),
        else => return error.TypeError,
    }
}

pub fn f_float_to_int(t: *Thread) Thread.Error!void {
    const a = try t.stack.pop();
    if (a != .Float) return error.TypeError;
    try t.stack.push(.{ .Int = @floatToInt(i32, a.Float) });
}

pub fn f_int_to_float(t: *Thread) Thread.Error!void {
    const a = try t.stack.pop();
    if (a != .Int) return error.TypeError;
    try t.stack.push(.{ .Float = @intToFloat(f32, a.Int) });
}

// bitwise ===

pub fn f_bnot(t: *Thread) Thread.Error!void {
    const val = try t.stack.pop();
    switch (val) {
        .Int => |i| try t.stack.push(.{ .Int = ~i }),
        else => return error.TypeError,
    }
}

pub fn f_band(t: *Thread) Thread.Error!void {
    const a = try t.stack.pop();
    const b = try t.stack.pop();
    if (@as(@TagType(Value), a) != b) return error.TypeError;
    switch (a) {
        .Int => |i| try t.stack.push(.{ .Int = i & b.Int }),
        else => return error.TypeError,
    }
}

pub fn f_bior(t: *Thread) Thread.Error!void {
    const a = try t.stack.pop();
    const b = try t.stack.pop();
    if (@as(@TagType(Value), a) != b) return error.TypeError;
    switch (a) {
        .Int => |i| try t.stack.push(.{ .Int = i | b.Int }),
        else => return error.TypeError,
    }
}

pub fn f_bxor(t: *Thread) Thread.Error!void {
    const a = try t.stack.pop();
    const b = try t.stack.pop();
    if (@as(@TagType(Value), a) != b) return error.TypeError;
    switch (a) {
        .Int => |i| try t.stack.push(.{ .Int = i ^ b.Int }),
        else => return error.TypeError,
    }
}

pub fn f_bshl(t: *Thread) Thread.Error!void {
    const amt = try t.stack.pop();
    const num = try t.stack.pop();
    if (@as(@TagType(Value), amt) != num) return error.TypeError;
    switch (num) {
        // TODO do something abt these casts
        .Int => |i| try t.stack.push(.{ .Int = num.Int << @intCast(u6, amt.Int) }),
        else => return error.TypeError,
    }
}

pub fn f_bshr(t: *Thread) Thread.Error!void {
    const amt = try t.stack.pop();
    const num = try t.stack.pop();
    if (@as(@TagType(Value), amt) != num) return error.TypeError;
    switch (num) {
        // TODO do something abt these casts
        .Int => |i| try t.stack.push(.{ .Int = num.Int >> @intCast(u6, amt.Int) }),
        else => return error.TypeError,
    }
}

pub fn f_integer_length(t: *Thread) Thread.Error!void {
    const num = try t.stack.pop();
    switch (num) {
        .Int => |i| {
            var ct: i64 = 0;
            var val = i;
            while (val > 0) : (val >>= 1) {
                ct += 1;
            }
            try t.stack.push(.{ .Int = ct });
        },
        else => return error.TypeError,
    }
}

// conditionals ===

pub fn f_choose(t: *Thread) Thread.Error!void {
    const if_false = try t.stack.pop();
    const if_true = try t.stack.pop();
    const condition = try t.stack.pop();
    if (condition != .Boolean) return error.TypeError;
    switch (condition) {
        .Boolean => |b| {
            if (b) {
                try t.stack.push(if_true);
                t.vm.dropValue(if_false);
            } else {
                try t.stack.push(if_false);
                t.vm.dropValue(if_true);
            }
        },
        else => return error.TypeError,
    }
}

fn areValuesEqual(a: Value, b: Value) bool {
    return if (@as(@TagType(Value), a) == b) switch (a) {
        .Int => |val| val == b.Int,
        .Float => |val| val == b.Float,
        .Char => |val| val == b.Char,
        .Boolean => |val| val == b.Boolean,
        .Sentinel => true,
        .String => |val| val.ptr == b.String.ptr and
            val.len == b.String.len,
        .Word => |val| val == b.Word,
        .Symbol => |val| val == b.Symbol,
        .Slice => |val| val.ptr == b.Slice.ptr and
            val.len == b.Slice.len,
        .FFI_Fn => |ptr| ptr.name == b.FFI_Fn.name and
            ptr.func == b.FFI_Fn.func,
        .FFI_Ptr => |ptr| ptr.type_id == b.FFI_Ptr.type_id and
            ptr.ptr == b.FFI_Ptr.ptr,
    } else false;
}

pub fn f_equal(t: *Thread) Thread.Error!void {
    const a = try t.stack.pop();
    const b = try t.stack.pop();
    const are_equal = areValuesEqual(a, b);
    t.vm.dropValue(a);
    t.vm.dropValue(b);
    try t.stack.push(.{ .Boolean = are_equal });
}

fn areValuesEquivalent(t: *Thread, a: Value, b: Value) bool {
    return if (@as(@TagType(Value), a) == b) switch (a) {
        .Int,
        .Float,
        .Boolean,
        .Char,
        .Sentinel,
        .Symbol,
        .Word,
        .FFI_Fn,
        => areValuesEqual(a, b),
        .String => |val| std.mem.eql(u8, val, b.String),
        // TODO do this differently so u dont use the zig stack?
        // could just use the return stack
        .Slice => |val| blk: {
            for (val) |v, i| {
                if (!areValuesEquivalent(t, v, b.Slice[i])) break :blk false;
            }
            break :blk true;
        },
        .FFI_Ptr => |ptr| t.vm.type_table.items[ptr.type_id].ty.FFI.equivalent_fn(t, ptr, b),
    } else blk: {
        // TODO
        break :blk false;
    };
}

pub fn f_equivalent(t: *Thread) Thread.Error!void {
    const a = try t.stack.pop();
    const b = try t.stack.pop();
    const are_equivalent = areValuesEquivalent(t, a, b);
    try t.stack.push(.{ .Boolean = are_equivalent });
    t.vm.dropValue(a);
    t.vm.dropValue(b);
}

pub fn f_not(t: *Thread) Thread.Error!void {
    const b = try t.stack.pop();
    if (b != .Boolean) return error.TypeError;
    try t.stack.push(.{ .Boolean = !b.Boolean });
}

pub fn f_and(t: *Thread) Thread.Error!void {
    const a = try t.stack.pop();
    const b = try t.stack.pop();
    if (a != .Boolean) return error.TypeError;
    if (b != .Boolean) return error.TypeError;
    try t.stack.push(.{ .Boolean = a.Boolean and b.Boolean });
}

pub fn f_or(t: *Thread) Thread.Error!void {
    const a = try t.stack.pop();
    const b = try t.stack.pop();
    if (a != .Boolean) return error.TypeError;
    if (b != .Boolean) return error.TypeError;
    try t.stack.push(.{ .Boolean = a.Boolean or b.Boolean });
}

// return stack ===

pub fn f_to_r(t: *Thread) Thread.Error!void {
    try t.return_stack.push(.{
        .value = try t.stack.pop(),
        .restore_ct = std.math.maxInt(usize),
    });
}

pub fn f_from_r(t: *Thread) Thread.Error!void {
    try t.stack.push((try t.return_stack.pop()).value);
}

pub fn f_peek_r(t: *Thread) Thread.Error!void {
    try t.stack.push(t.vm.dupValue((try t.return_stack.peek()).value));
}

// shuffle ===

pub fn f_drop(t: *Thread) Thread.Error!void {
    const val = try t.stack.pop();
    t.vm.dropValue(val);
}

pub fn f_dup(t: *Thread) Thread.Error!void {
    const val = try t.stack.peek();
    try t.stack.push(t.vm.dupValue(val));
}

pub fn f_over(t: *Thread) Thread.Error!void {
    const val = (try t.stack.index(1)).*;
    try t.stack.push(t.vm.dupValue(val));
}

pub fn f_pick(t: *Thread) Thread.Error!void {
    const val = (try t.stack.index(2)).*;
    try t.stack.push(t.vm.dupValue(val));
}

pub fn f_swap(t: *Thread) Thread.Error!void {
    var slice = t.stack.data.items;
    if (slice.len < 2) return error.StackUnderflow;
    std.mem.swap(Value, &slice[slice.len - 1], &slice[slice.len - 2]);
}

// slices ===

pub fn f_slice_len(t: *Thread) Thread.Error!void {
    const slc = try t.stack.pop();
    if (slc != .Slice) return error.TypeError;
    try t.stack.push(.{ .Int = @intCast(i64, slc.Slice.len) });
}

pub fn f_slice_get(t: *Thread) Thread.Error!void {
    const slc = try t.stack.pop();
    const idx = try t.stack.pop();
    if (slc != .Slice) return error.TypeError;
    if (idx != .Int) return error.TypeError;
    try t.stack.push(t.vm.dupValue(slc.Slice[@intCast(usize, idx.Int)]));
}

// Rc ===
// pub fn Rc2(comptime T: type) type {
//     return struct {
//         const Self = @This();
//
//         pub const Ref = struct {
//             rc: *Self,
//
//             pub fn downgrade(ref: Ref) Weak {
//                 ref.rc.ref_ct -= 1;
//                 ref.rc.weak_ct += 1;
//                 return .{ .rc = ref.rc };
//             }
//         };
//
//         pub const Weak = struct {
//             rc: *Self,
//
//             pub fn upgrade(weak: Weak) Ref {
//                 weak.rc.weak_ct -= 1;
//                 weak.rc.ref_ct += 1;
//                 return .{ .rc = weak.rc };
//             }
//         };
//
//         obj: T,
//         ref_ct: usize,
//         weak_ct: usize,
//
//         pub fn init() Self {
//             return .{
//                 .obj = undefined,
//                 .ref_ct = 0,
//             };
//         }
//
//         pub fn makeOne(allocator: *Allocator) Allocator.Error!*Self {
//             var rc = try allocator.create(Rc(T));
//             rc.* = Rc(T).init();
//             rc.inc();
//             return rc;
//         }
//
//         pub fn ref(self: *Self) Ref {
//             self.ref_ct += 1;
//             return .{ .rc = self };
//         }
//
//         pub fn refWeak(self: *Self) Weak {
//             self.weak_ct += 1;
//             return .{ .rc = self };
//         }
//
//         pub fn drop(self: *Self) bool {
//         }
//
//         pub fn dropWeak(self: *Self) bool {
//         }
//
//         //         pub fn inc(self: *Self) void {
//         //             self.ref_ct += 1;
//         //         }
//         //
//         //         // returns if the obj is alive or not
//         //         pub fn dec(self: *Self) bool {
//         //             std.debug.assert(self.ref_ct > 0);
//         //             self.ref_ct -= 1;
//         //             return self.ref_ct != 0;
//         //         }
//     };
// }
//
pub fn Rc(comptime T: type) type {
    return struct {
        const Self = @This();

        obj: T,
        ref_ct: usize,

        pub fn init() Self {
            return .{
                .obj = undefined,
                .ref_ct = 0,
            };
        }

        pub fn makeOne(allocator: *Allocator) Allocator.Error!*Self {
            var rc = try allocator.create(Rc(T));
            rc.* = Rc(T).init();
            rc.inc();
            return rc;
        }

        pub fn inc(self: *Self) void {
            self.ref_ct += 1;
        }

        // returns if the obj is alive or not
        pub fn dec(self: *Self) bool {
            std.debug.assert(self.ref_ct > 0);
            self.ref_ct -= 1;
            return self.ref_ct != 0;
        }
    };
}

// string ===

// TODO separate out code that takes a literal string
pub const ft_string = struct {
    const Self = @This();

    pub const String = ArrayList(u8);

    var type_id: usize = undefined;

    pub fn install(vm: *VM) Allocator.Error!void {
        type_id = try vm.installType("string", .{
            .ty = .{
                .FFI = .{
                    .display_fn = display,
                    .dup_fn = dup,
                    .drop_fn = drop,
                },
            },
        });
    }

    pub fn display(t: *Thread, ptr: FFI_Ptr) void {
        const rc = ptr.cast(Rc(String));
        std.debug.print("\"{}\"", .{rc.obj.items});
    }

    pub fn dup(vm: *VM, ptr: FFI_Ptr) FFI_Ptr {
        var rc = ptr.cast(Rc(String));
        rc.inc();
        return .{
            .type_id = type_id,
            .ptr = @ptrCast(*FFI_Ptr.Ptr, rc),
        };
    }

    pub fn drop(vm: *VM, ptr: FFI_Ptr) void {
        var rc = ptr.cast(Rc(String));
        if (!rc.dec()) {
            rc.obj.deinit();
            vm.allocator.destroy(rc);
        }
    }

    //;

    fn makeRcFromSlice(allocator: *Allocator, slice: []const u8) Allocator.Error!*Rc(String) {
        var rc = try Rc(String).makeOne(allocator);
        rc.obj = String.init(allocator);
        try rc.obj.appendSlice(slice);
        return rc;
    }

    fn makeRcMoveSlice(allocator: *Allocator, slice: []u8) Allocator.Error!*Rc(String) {
        var rc = try Rc(String).makeOne(allocator);
        rc.obj = String.fromOwnedSlice(allocator, slice);
        return rc;
    }

    pub fn _make(t: *Thread) Thread.Error!void {
        var rc = try Rc(String).makeOne(t.vm.allocator);
        rc.obj = String.init(t.vm.allocator);
        try t.stack.push(.{
            .FFI_Ptr = .{
                .type_id = type_id,
                .ptr = @ptrCast(*FFI_Ptr.Ptr, rc),
            },
        });
    }

    pub fn _clone(t: *Thread) Thread.Error!void {
        const other = try t.stack.pop();
        switch (other) {
            .String => |str| {
                var rc = try makeRcFromSlice(t.vm.allocator, str);
                try t.stack.push(.{
                    .FFI_Ptr = .{
                        .type_id = type_id,
                        .ptr = @ptrCast(*FFI_Ptr.Ptr, rc),
                    },
                });
            },
            .FFI_Ptr => |ptr| {
                if (ptr.type_id != type_id) return error.TypeError;

                var other_rc = ptr.cast(Rc(String));
                var rc = try makeRcFromSlice(t.vm.allocator, other_rc.obj.items);

                try t.stack.push(.{
                    .FFI_Ptr = .{
                        .type_id = type_id,
                        .ptr = @ptrCast(*FFI_Ptr.Ptr, rc),
                    },
                });

                t.vm.dropValue(other);
            },
            else => return error.TypeError,
        }
    }

    // TODO should u switch this and other here
    // "abc" "def" string-append!
    // "def" "abc" string-append!
    // { swap string-append! } :++ @
    pub fn _append_in_place(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const other = try t.stack.pop();
        switch (other) {
            .String => {},
            .FFI_Ptr => |ptr| {
                if (ptr.type_id != type_id) return error.TypeError;
            },
            else => return error.TypeError,
        }

        const rc = switch (this) {
            .String => |str| try makeRcFromSlice(t.vm.allocator, str),
            .FFI_Ptr => |ptr| blk: {
                if (ptr.type_id != type_id) return error.TypeError;
                break :blk ptr.cast(Rc(String));
            },
            else => return error.TypeError,
        };

        switch (other) {
            .String => |o_str| try rc.obj.appendSlice(o_str),
            .FFI_Ptr => |o_ptr| {
                const o_str = o_ptr.cast(Rc(String)).obj.items;
                try rc.obj.appendSlice(o_str);
            },
            else => unreachable,
        }

        try t.stack.push(.{
            .FFI_Ptr = .{
                .type_id = type_id,
                .ptr = @ptrCast(*FFI_Ptr.Ptr, rc),
            },
        });

        t.vm.dropValue(other);
    }

    pub fn _to_symbol(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const str = switch (this) {
            .String => |str| str,
            .FFI_Ptr => |ptr| blk: {
                if (ptr.type_id != type_id) return error.TypeError;
                break :blk ptr.cast(Rc(String)).obj.items;
            },
            else => return error.TypeError,
        };
        try t.stack.push(.{ .Symbol = try t.vm.internSymbol(str) });
        t.vm.dropValue(this);
    }

    pub fn _get(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const idx = try t.stack.pop();
        if (this != .FFI_Ptr and this != .String) return error.TypeError;
        if (this == .FFI_Ptr and this.FFI_Ptr.type_id != type_id) return error.TypeError;
        if (idx != .Int) return error.TypeError;

        switch (this) {
            .String => |s| {
                try t.stack.push(.{ .Char = s[@intCast(usize, idx.Int)] });
            },
            .FFI_Ptr => |ptr| {
                var rc = ptr.cast(Rc(String));
                try t.stack.push(.{ .Char = rc.obj.items[@intCast(usize, idx.Int)] });
            },
            else => unreachable,
        }

        t.vm.dropValue(this);
    }

    pub fn _len(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        if (this != .FFI_Ptr or this != .String) return error.TypeError;
        if (this == .FFI_Ptr and this.FFI_Ptr.type_id != type_id) return error.TypeError;

        switch (this) {
            .String => |s| {
                try t.stack.push(.{ .Int = @intCast(i32, s.len) });
            },
            .FFI_Ptr => |ptr| {
                var rc = ptr.cast(Rc(String));
                try t.stack.push(.{ .Int = @intCast(i32, rc.obj.items.len) });
            },
            else => unreachable,
        }

        t.vm.dropValue(this);
    }
};

// record ===

pub const ft_record = struct {
    const Self = @This();

    pub const Record = []Value;

    var type_id: usize = undefined;
    var weak_type_id: usize = undefined;

    pub fn install(vm: *VM) Allocator.Error!void {
        type_id = try vm.installType("record2", .{
            .ty = .{
                .FFI = .{
                    .display_fn = display,
                    .dup_fn = dup,
                    .drop_fn = drop,
                },
            },
        });
        weak_type_id = try vm.installType("weak-record2", .{
            .ty = .{
                .FFI = .{
                    .display_fn = display_weak,
                },
            },
        });
    }

    pub fn display(t: *Thread, ptr: FFI_Ptr) void {
        const rc = ptr.cast(Rc(Record));
        std.debug.print("r< ", .{});
        for (rc.obj) |v| {
            t.nicePrintValue(v);
            std.debug.print(" ", .{});
        }
        std.debug.print(">", .{});
    }

    pub fn dup(vm: *VM, ptr: FFI_Ptr) FFI_Ptr {
        var rc = ptr.cast(Rc(Record));
        rc.inc();
        return .{
            .type_id = type_id,
            .ptr = @ptrCast(*FFI_Ptr.Ptr, rc),
        };
    }

    pub fn drop(vm: *VM, ptr: FFI_Ptr) void {
        var rc = ptr.cast(Rc(Record));
        if (!rc.dec()) {
            for (rc.obj) |val| {
                vm.dropValue(val);
            }
            vm.allocator.free(rc.obj);
            vm.allocator.destroy(rc);
        }
    }

    pub fn display_weak(t: *Thread, ptr: FFI_Ptr) void {
        const rc = ptr.cast(Rc(Record));
        std.debug.print("r@({x} {})", .{ @ptrToInt(rc), rc.obj.len });
    }

    pub fn _make(t: *Thread) Thread.Error!void {
        const slot_ct = try t.stack.pop();
        if (slot_ct != .Int) return error.TypeError;

        var rc = try Rc(Record).makeOne(t.vm.allocator);
        rc.obj = try t.vm.allocator.alloc(Value, @intCast(usize, slot_ct.Int));
        for (rc.obj) |*v| {
            v.* = .{ .Sentinel = {} };
        }
        try t.stack.push(.{
            .FFI_Ptr = .{
                .type_id = type_id,
                .ptr = @ptrCast(*FFI_Ptr.Ptr, rc),
            },
        });
    }

    pub fn _downgrade(t: *Thread) Thread.Error!void {
        const this = try t.stack.index(0);
        if (this.* != .FFI_Ptr) return error.TypeError;
        if (this.*.FFI_Ptr.type_id != type_id) return error.TypeError;
        const rc = this.FFI_Ptr.cast(Rc(Record));
        const ref_ct = rc.ref_ct;
        t.vm.dropValue(this.*);
        if (ref_ct > 1) {
            this.*.FFI_Ptr.type_id = weak_type_id;
        }
    }

    pub fn _upgrade(t: *Thread) Thread.Error!void {
        const this = try t.stack.index(0);
        if (this.* != .FFI_Ptr) return error.TypeError;
        if (this.*.FFI_Ptr.type_id != weak_type_id) return error.TypeError;
        this.*.FFI_Ptr.type_id = type_id;
        var rc = this.*.FFI_Ptr.cast(Rc(Record));
        rc.inc();
    }

    pub fn _set(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const idx = try t.stack.pop();
        const val = try t.stack.pop();
        if (this != .FFI_Ptr) return error.TypeError;
        if (this.FFI_Ptr.type_id != type_id) return error.TypeError;
        if (idx != .Int) return error.TypeError;

        var rc = this.FFI_Ptr.cast(Rc(Record));
        rc.obj[@intCast(usize, idx.Int)] = val;

        t.vm.dropValue(this);
    }

    pub fn _get(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const idx = try t.stack.pop();
        if (this != .FFI_Ptr) return error.TypeError;
        if (this.FFI_Ptr.type_id != type_id) return error.TypeError;
        if (idx != .Int) return error.TypeError;

        var rc = this.FFI_Ptr.cast(Rc(Record));
        try t.stack.push(t.vm.dupValue(rc.obj[@intCast(usize, idx.Int)]));

        t.vm.dropValue(this);
    }
};

// vec ===

// TODO vec insert, vec append
// non mutating versions of fns
pub const ft_vec = struct {
    const Self = @This();

    pub const Vec = ArrayList(Value);

    var type_id: usize = undefined;
    var weak_type_id: usize = undefined;

    pub fn install(vm: *VM) Allocator.Error!void {
        type_id = try vm.installType("vec", .{
            .ty = .{
                .FFI = .{
                    .display_fn = display,
                    .dup_fn = dup,
                    .drop_fn = drop,
                },
            },
        });
        weak_type_id = try vm.installType("weak-vec", .{
            .ty = .{
                .FFI = .{
                    .display_fn = display_weak,
                },
            },
        });
    }

    pub fn display(t: *Thread, ptr: FFI_Ptr) void {
        const rc = ptr.cast(Rc(Vec));
        std.debug.print("v[ ", .{});
        for (rc.obj.items) |v| {
            t.nicePrintValue(v);
            std.debug.print(" ", .{});
        }
        std.debug.print("]", .{});
    }

    pub fn dup(vm: *VM, ptr: FFI_Ptr) FFI_Ptr {
        var rc = ptr.cast(Rc(Vec));
        rc.inc();
        return .{
            .type_id = type_id,
            .ptr = @ptrCast(*FFI_Ptr.Ptr, rc),
        };
    }

    pub fn drop(vm: *VM, ptr: FFI_Ptr) void {
        var rc = ptr.cast(Rc(Vec));
        if (!rc.dec()) {
            for (rc.obj.items) |val| {
                vm.dropValue(val);
            }
            rc.obj.deinit();
            vm.allocator.destroy(rc);
        }
    }

    pub fn display_weak(t: *Thread, ptr: FFI_Ptr) void {
        const rc = ptr.cast(Rc(Vec));
        std.debug.print("v@({x} {})", .{ @ptrToInt(rc), rc.obj.items.len });
    }

    //;

    pub fn _make(t: *Thread) Thread.Error!void {
        var rc = try Rc(Vec).makeOne(t.vm.allocator);
        rc.obj = Vec.init(t.vm.allocator);
        try t.stack.push(.{
            .FFI_Ptr = .{
                .type_id = type_id,
                .ptr = @ptrCast(*FFI_Ptr.Ptr, rc),
            },
        });
    }

    pub fn _make_capacity(t: *Thread) Thread.Error!void {
        const capacity = try t.stack.pop();
        if (capacity != .Int) return error.TypeError;

        var rc = try Rc(Vec).makeOne(t.vm.allocator);
        rc.obj = try Vec.initCapacity(
            t.vm.allocator,
            @intCast(usize, capacity.Int),
        );

        try t.stack.push(.{
            .FFI_Ptr = .{
                .type_id = type_id,
                .ptr = @ptrCast(*FFI_Ptr.Ptr, rc),
            },
        });
    }

    pub fn _downgrade(t: *Thread) Thread.Error!void {
        const this = try t.stack.index(0);
        if (this.* != .FFI_Ptr) return error.TypeError;
        if (this.*.FFI_Ptr.type_id != type_id) return error.TypeError;
        const rc = this.FFI_Ptr.cast(Rc(Vec));
        const ref_ct = rc.ref_ct;
        t.vm.dropValue(this.*);
        if (ref_ct > 1) {
            this.*.FFI_Ptr.type_id = weak_type_id;
        }
    }

    pub fn _upgrade(t: *Thread) Thread.Error!void {
        const this = try t.stack.index(0);
        if (this.* != .FFI_Ptr) return error.TypeError;
        if (this.*.FFI_Ptr.type_id != weak_type_id) return error.TypeError;
        this.*.FFI_Ptr.type_id = type_id;
        var rc = this.*.FFI_Ptr.cast(Rc(Vec));
        rc.inc();
    }

    pub fn _to_slice(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        if (this != .FFI_Ptr) return error.TypeError;
        if (this.FFI_Ptr.type_id != type_id and
            this.FFI_Ptr.type_id != weak_type_id) return error.TypeError;

        var rc = this.FFI_Ptr.cast(Rc(Vec));
        const slc = try t.vm.allocator.dupe(Value, rc.obj.items);
        try t.vm.slice_literals.append(.{ .Slice = slc });
        try t.stack.push(.{ .Slice = slc });
        t.vm.dropValue(this);
    }

    pub fn _push(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const val = try t.stack.pop();
        if (this != .FFI_Ptr) return error.TypeError;
        if (this.FFI_Ptr.type_id != type_id and
            this.FFI_Ptr.type_id != weak_type_id) return error.TypeError;

        var rc = this.FFI_Ptr.cast(Rc(Vec));
        try rc.obj.append(val);

        t.vm.dropValue(this);
    }

    pub fn _set(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const idx = try t.stack.pop();
        const val = try t.stack.pop();
        if (this != .FFI_Ptr) return error.TypeError;
        if (this.FFI_Ptr.type_id != type_id and
            this.FFI_Ptr.type_id != weak_type_id) return error.TypeError;
        if (idx != .Int) return error.TypeError;

        var rc = this.FFI_Ptr.cast(Rc(Vec));
        t.vm.dropValue(rc.obj.items[@intCast(usize, idx.Int)]);
        rc.obj.items[@intCast(usize, idx.Int)] = val;

        t.vm.dropValue(this);
    }

    pub fn _get(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const idx = try t.stack.pop();
        if (this != .FFI_Ptr) return error.TypeError;
        if (this.FFI_Ptr.type_id != type_id and
            this.FFI_Ptr.type_id != weak_type_id) return error.TypeError;
        if (idx != .Int) return error.TypeError;

        var rc = this.FFI_Ptr.cast(Rc(Vec));
        try t.stack.push(t.vm.dupValue(rc.obj.items[@intCast(usize, idx.Int)]));

        t.vm.dropValue(this);
    }

    pub fn _len(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        if (this != .FFI_Ptr) return error.TypeError;
        if (this.FFI_Ptr.type_id != type_id and
            this.FFI_Ptr.type_id != weak_type_id) return error.TypeError;

        var rc = this.FFI_Ptr.cast(Rc(Vec));
        try t.stack.push(.{ .Int = @intCast(i32, rc.obj.items.len) });

        t.vm.dropValue(this);
    }

    pub fn _reverse_in_place(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        if (this != .FFI_Ptr) return error.TypeError;
        if (this.FFI_Ptr.type_id != type_id and
            this.FFI_Ptr.type_id != weak_type_id) return error.TypeError;

        var rc = this.FFI_Ptr.cast(Rc(Vec));
        std.mem.reverse(Value, rc.obj.items);

        t.vm.dropValue(this);
    }
};

// file ==

pub const ft_file = struct {
    const Self = @This();

    pub const File = struct {
        filepath: []u8,
        file: std.fs.File,
    };

    pub var type_id: usize = undefined;

    pub fn install(vm: *VM) Allocator.Error!void {
        type_id = try vm.installType("file", .{
            .ty = .{
                .FFI = .{
                    .display_fn = display,
                    .dup_fn = dup,
                    .drop_fn = drop,
                },
            },
        });
    }

    pub fn display(t: *Thread, ptr: FFI_Ptr) void {
        const rc = ptr.cast(Rc(File));
        std.debug.print("f({})", .{rc.obj.filepath});
    }

    pub fn dup(vm: *VM, ptr: FFI_Ptr) FFI_Ptr {
        var rc = ptr.cast(Rc(File));
        rc.inc();
        return .{
            .type_id = type_id,
            .ptr = @ptrCast(*FFI_Ptr.Ptr, rc),
        };
    }

    pub fn drop(vm: *VM, ptr: FFI_Ptr) void {
        var rc = ptr.cast(Rc(File));
        if (!rc.dec()) {
            vm.allocator.free(rc.obj.filepath);
            rc.obj.file.close();
            vm.allocator.destroy(rc);
        }
    }

    //;

    // TODO
    //   file close

    // TODO there could be an error if <file>,std is called more than once
    //   and orth tries to close one of the files twice
    pub fn _std(t: *Thread) Thread.Error!void {
        const which = try t.stack.pop();
        if (which != .Symbol) return error.TypeError;

        var f: std.fs.File = undefined;
        var fp: []const u8 = undefined;
        if (which.Symbol == try t.vm.internSymbol("in")) {
            f = std.io.getStdIn();
            fp = "stdin";
        } else if (which.Symbol == try t.vm.internSymbol("out")) {
            f = std.io.getStdOut();
            fp = "stdout";
        } else if (which.Symbol == try t.vm.internSymbol("err")) {
            f = std.io.getStdErr();
            fp = "stderr";
        } else {
            // TODO
            return error.Panic;
        }

        var rc = try Rc(File).makeOne(t.vm.allocator);
        rc.obj = .{
            .filepath = try t.vm.allocator.dupe(u8, fp),
            .file = f,
        };
        try t.stack.push(.{
            .FFI_Ptr = .{
                .type_id = type_id,
                .ptr = @ptrCast(*FFI_Ptr.Ptr, rc),
            },
        });
        try t.stack.push(.{ .Boolean = true });
    }

    pub fn _open(t: *Thread) Thread.Error!void {
        // TODO allow ffi string
        //  want to use a symbol or array or something for open_flags
        const path = try t.stack.pop();
        const open_flags = try t.stack.pop();
        if (path != .String) return error.TypeError;
        if (open_flags != .String) return error.TypeError;

        var flags = std.fs.File.OpenFlags{
            .read = false,
        };
        for (open_flags.String) |ch| {
            if (ch == 'r' or ch == 'R') flags.read = true;
            if (ch == 'w' or ch == 'W') flags.write = true;
        }

        var f = std.fs.cwd().openFile(path.String, flags) catch |err| {
            try t.stack.push(.{ .String = "couldn't load file" });
            try t.stack.push(.{ .Boolean = false });
            return;
        };
        errdefer f.close();

        var rc = try Rc(File).makeOne(t.vm.allocator);
        rc.obj = .{
            .filepath = try t.vm.allocator.dupe(u8, path.String),
            .file = f,
        };
        try t.stack.push(.{
            .FFI_Ptr = .{
                .type_id = type_id,
                .ptr = @ptrCast(*FFI_Ptr.Ptr, rc),
            },
        });
        try t.stack.push(.{ .Boolean = true });
    }

    pub fn _read_char(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        if (this != .FFI_Ptr) return error.TypeError;
        if (this.FFI_Ptr.type_id != type_id) return error.TypeError;

        var rc = this.FFI_Ptr.cast(Rc(File));
        var buf = [1]u8{undefined};
        // TODO handle read errors
        const ct = rc.obj.file.read(&buf) catch unreachable;
        if (ct == 0) {
            try t.stack.push(.{ .Boolean = false });
            try t.stack.push(.{ .Boolean = false });
        } else {
            try t.stack.push(.{ .Char = buf[0] });
            try t.stack.push(.{ .Boolean = true });
        }
        t.vm.dropValue(this);
    }

    pub fn _read_all(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        if (this != .FFI_Ptr) return error.TypeError;
        if (this.FFI_Ptr.type_id != type_id) return error.TypeError;

        var rc = this.FFI_Ptr.cast(Rc(File));
        // TODO
        rc.obj.file.seekTo(0) catch unreachable;
        const buf = rc.obj.file.readToEndAlloc(t.vm.allocator, std.math.maxInt(usize)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => unreachable,
        };

        var rc_str = try ft_string.makeRcMoveSlice(t.vm.allocator, buf);
        try t.stack.push(.{
            .FFI_Ptr = .{
                .type_id = ft_string.type_id,
                .ptr = @ptrCast(*FFI_Ptr.Ptr, rc_str),
            },
        });
        try t.stack.push(.{ .Boolean = true });

        t.vm.dropValue(this);
    }

    pub fn _write_char(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const ch = try t.stack.pop();
        if (this != .FFI_Ptr) return error.TypeError;
        if (this.FFI_Ptr.type_id != type_id) return error.TypeError;
        if (ch != .Char) return error.TypeError;

        const buf = [1]u8{ch.Char};

        var rc = this.FFI_Ptr.cast(Rc(File));
        rc.obj.file.writeAll(&buf) catch unreachable;

        t.vm.dropValue(this);
    }

    pub fn _write_all(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const str = try t.stack.pop();
        if (this != .FFI_Ptr) return error.TypeError;
        if (this.FFI_Ptr.type_id != type_id) return error.TypeError;
        // TODO take ffi string
        if (str != .String) return error.TypeError;

        var rc = this.FFI_Ptr.cast(Rc(File));
        rc.obj.file.writeAll(str.String) catch unreachable;

        t.vm.dropValue(this);
    }
};

// map ===

// TODO
// mref vs mget ?   'mget eval' isnt bad or 'meval'
//   where mget should evaluate whatever it gets out of the map
//   and mref should just push it
// equals
pub const ft_map = struct {
    const Self = @This();

    pub const Map = std.AutoHashMap(usize, Value);

    pub var type_id: usize = undefined;

    pub fn install(vm: *VM) Allocator.Error!void {
        type_id = try vm.installType("map", .{
            .ty = .{
                .FFI = .{
                    .display_fn = display,
                    .dup_fn = dup,
                    .drop_fn = drop,
                },
            },
        });
    }

    pub fn display(t: *Thread, ptr: FFI_Ptr) void {
        const rc = ptr.cast(Rc(Map));
        std.debug.print("m[ ", .{});
        var iter = rc.obj.iterator();
        while (iter.next()) |entry| {
            std.debug.print("{} ", .{t.vm.symbol_table.items[entry.key]});
            t.nicePrintValue(entry.value);
            std.debug.print(" ", .{});
        }
        std.debug.print("]", .{});
    }

    pub fn dup(vm: *VM, ptr: FFI_Ptr) FFI_Ptr {
        var rc = ptr.cast(Rc(Map));
        rc.inc();
        return .{
            .type_id = type_id,
            .ptr = @ptrCast(*FFI_Ptr.Ptr, rc),
        };
    }

    pub fn drop(vm: *VM, ptr: FFI_Ptr) void {
        var rc = ptr.cast(Rc(Map));
        if (!rc.dec()) {
            var iter = rc.obj.iterator();
            while (iter.next()) |entry| {
                vm.dropValue(entry.value);
            }
            rc.obj.deinit();
            vm.allocator.destroy(rc);
        }
    }

    //;

    pub fn _make(t: *Thread) Thread.Error!void {
        var rc = try Rc(Map).makeOne(t.vm.allocator);
        errdefer t.vm.allocator.destroy(rc);
        rc.obj = Map.init(t.vm.allocator);
        try t.stack.push(.{
            .FFI_Ptr = .{
                .type_id = type_id,
                .ptr = @ptrCast(*FFI_Ptr.Ptr, rc),
            },
        });
    }

    pub fn _set(t: *Thread) Thread.Error!void {
        const map = try t.stack.pop();
        const sym = try t.stack.pop();
        const value = try t.stack.pop();
        if (sym != .Symbol) return error.TypeError;
        if (map != .FFI_Ptr) return error.TypeError;
        if (map.FFI_Ptr.type_id != type_id) return error.TypeError;

        var rc = map.FFI_Ptr.cast(Rc(Map));

        // TODO handle overwrite
        try rc.obj.put(sym.Symbol, value);

        t.vm.dropValue(map);
    }

    pub fn _get(t: *Thread) Thread.Error!void {
        const map = try t.stack.pop();
        const sym = try t.stack.pop();
        if (sym != .Symbol) return error.TypeError;
        if (map != .FFI_Ptr) return error.TypeError;
        if (map.FFI_Ptr.type_id != type_id) return error.TypeError;

        var rc = map.FFI_Ptr.cast(Rc(Map));

        if (rc.obj.get(sym.Symbol)) |val| {
            try t.stack.push(t.vm.dupValue(val));
            try t.stack.push(.{ .Boolean = true });
        } else {
            try t.stack.push(.{ .String = "not found" });
            try t.stack.push(.{ .Boolean = false });
        }

        t.vm.dropValue(map);
    }
};

// =====

const BuiltinDefinition = struct {
    name: []const u8,
    func: FFI_Fn.Function,
};

pub const builtins = [_]BuiltinDefinition{
    .{ .name = "panic", .func = f_panic },
    .{ .name = "@", .func = f_define },
    .{ .name = "def", .func = f_def },
    .{ .name = "ref", .func = f_ref },
    .{ .name = "eval'", .func = f_eval },
    .{ .name = "eval,restore'", .func = f_eval_restore },
    .{ .name = ">restore", .func = f_push_restore },

    .{ .name = "stack-len", .func = f_stack_len },
    .{ .name = "stack-index", .func = f_stack_index },
    .{ .name = "clear-stack", .func = f_clear_stack },

    .{ .name = ".stack'", .func = f_print_stack },
    .{ .name = ".rstack'", .func = f_print_rstack },
    .{ .name = ".current'", .func = f_print_current },

    .{ .name = "display", .func = f_display },

    .{ .name = "read", .func = f_read },
    .{ .name = "parse", .func = f_parse },

    .{ .name = "value-type-of", .func = f_value_type_of },
    .{ .name = "ffi-type-of", .func = f_ffi_type_of },
    .{ .name = "word>symbol", .func = f_word_to_symbol },
    .{ .name = "symbol>word", .func = f_symbol_to_word },
    .{ .name = "symbol>string", .func = f_symbol_to_string },

    .{ .name = "neg", .func = f_negative },
    .{ .name = "+", .func = f_plus },
    .{ .name = "-", .func = f_minus },
    .{ .name = "*", .func = f_times },
    .{ .name = "/", .func = f_divide },
    .{ .name = "mod", .func = f_mod },
    .{ .name = "rem", .func = f_rem },
    .{ .name = "<", .func = f_lt },
    .{ .name = "=", .func = f_number_equal },
    .{ .name = "float>int", .func = f_float_to_int },
    .{ .name = "int>float", .func = f_int_to_float },

    .{ .name = "~", .func = f_bnot },
    .{ .name = "&", .func = f_band },
    .{ .name = "|", .func = f_bior },
    .{ .name = "^", .func = f_bxor },
    .{ .name = "<<", .func = f_bshl },
    .{ .name = ">>", .func = f_bshr },
    .{ .name = "integer-length", .func = f_integer_length },

    .{ .name = "?", .func = f_choose },
    .{ .name = "eq?", .func = f_equal },
    .{ .name = "eqv?", .func = f_equivalent },
    .{ .name = "not", .func = f_not },
    .{ .name = "and", .func = f_and },
    .{ .name = "or", .func = f_or },

    .{ .name = ">R", .func = f_to_r },
    .{ .name = "<R", .func = f_from_r },
    .{ .name = ".R", .func = f_peek_r },

    .{ .name = "drop", .func = f_drop },
    .{ .name = "dup", .func = f_dup },
    .{ .name = "over", .func = f_over },
    .{ .name = "pick", .func = f_pick },
    .{ .name = "swap", .func = f_swap },

    .{ .name = "slen", .func = f_slice_len },
    .{ .name = "sget", .func = f_slice_get },

    .{ .name = "<string>", .func = ft_string._make },
    .{ .name = "<string>,clone", .func = ft_string._clone },
    .{ .name = "string-append!", .func = ft_string._append_in_place },
    .{ .name = "string>symbol", .func = ft_string._to_symbol },
    .{ .name = "strget", .func = ft_string._get },
    .{ .name = "strlen", .func = ft_string._len },

    .{ .name = "<record>", .func = ft_record._make },
    .{ .name = "rset!", .func = ft_record._set },
    .{ .name = "rget", .func = ft_record._get },
    .{ .name = "rdowngrade", .func = ft_record._downgrade },
    .{ .name = "rupgrade", .func = ft_record._upgrade },

    .{ .name = "<vec>", .func = ft_vec._make },
    .{ .name = "<vec>,capacity", .func = ft_vec._make_capacity },
    .{ .name = "vdowngrade", .func = ft_vec._downgrade },
    .{ .name = "vupgrade", .func = ft_vec._upgrade },
    .{ .name = "vec>slice", .func = ft_vec._to_slice },
    .{ .name = "vpush!", .func = ft_vec._push },
    .{ .name = "vset!", .func = ft_vec._set },
    .{ .name = "vget", .func = ft_vec._get },
    .{ .name = "vlen", .func = ft_vec._len },
    .{ .name = "vreverse!", .func = ft_vec._reverse_in_place },

    .{ .name = "<map>", .func = ft_map._make },
    .{ .name = "mget*", .func = ft_map._get },
    .{ .name = "mset!", .func = ft_map._set },

    .{ .name = "<file>,open", .func = ft_file._open },
    .{ .name = "<file>,std", .func = ft_file._std },
    .{ .name = "file-read-char", .func = ft_file._read_char },
    .{ .name = "file-read-all", .func = ft_file._read_all },
    .{ .name = "file-write-char", .func = ft_file._write_char },
    .{ .name = "file-write-all", .func = ft_file._write_all },
};
