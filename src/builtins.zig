const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const lib = @import("lib.zig");
usingnamespace lib;

//;

// typecheck after you get all the args u want

// display is human readable
// write is machine readable

// dont have ffi quotations
//   any new quotations generated can be interned from vectors
//   like strings and symbols

//;

// TODO need
// ports
//   displayp writep
//   string, file, stdin/err/out, vector port
//   write an iterator to a port
// self referential rc pointers need to be weak
//   you only need words that put things in collections to worry about weak pointers
//   handle circular references somehow when printing
// all returns of error.TypeError report what was expected
// functions
//   text
//     string manipulation
//     string format
//     printing functions
//       write
//         need to translate '\n' in strings to a "\n"
//   thread exit
//   array access words
//   math stuff
//     handle integer overflow
//       check where it can happen and make it a Thread.Error or change + to +%
// types
//   make sure accessing them from within zig is easy
// short circuiting and and or

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
        t.vm.dropValue(prev);
    }
    t.vm.word_table.items[name.Symbol] = value;
}

pub fn f_define_record_type(t: *Thread) Thread.Error!void {
    const name = try t.stack.pop();
    const fields = try t.stack.pop();
    if (name != .Symbol) return error.TypeError;
    if (fields != .Array) return error.TypeError;
    for (fields.Array) |sym| {
        if (sym != .Symbol) return error.TypeError;
    }

    const slot_ct = fields.Array.len;

    const idx = t.vm.type_table.items.len;
    try t.vm.type_table.append(.{
        .name_id = name.Symbol,
        .ty = .{
            .Record = .{
                .slot_ct = slot_ct,
            },
        },
    });

    const name_str = t.vm.symbol_table.items[name.Symbol];

    {
        const constructor = try std.fmt.allocPrint(t.vm.allocator, "make-{}", .{name_str});
        defer t.vm.allocator.free(constructor);

        var q = try t.vm.allocator.alloc(Value, 2 + slot_ct * 5);
        try t.vm.quotation_literals.append(.{ .Quotation = q });
        q[0] = .{ .Int = @intCast(i64, idx) };
        q[1] = .{ .Word = t.vm.internSymbol("<record>") catch unreachable };
        var i: usize = 0;
        while (i < slot_ct) : (i += 1) {
            q[2 + (slot_ct - i - 1) * 5] = .{ .Word = t.vm.internSymbol("swap") catch unreachable };
            q[3 + (slot_ct - i - 1) * 5] = .{ .Word = t.vm.internSymbol("over") catch unreachable };
            q[4 + (slot_ct - i - 1) * 5] = .{ .Int = @intCast(i64, i) };
            q[5 + (slot_ct - i - 1) * 5] = .{ .Word = t.vm.internSymbol("swap") catch unreachable };
            q[6 + (slot_ct - i - 1) * 5] = .{ .Word = t.vm.internSymbol("rset!") catch unreachable };
        }

        try t.vm.defineWord(constructor, .{ .Quotation = q });
    }

    {
        const predicate = try std.fmt.allocPrint(t.vm.allocator, "{}?", .{name_str});
        defer t.vm.allocator.free(predicate);

        var q = try t.vm.allocator.alloc(Value, 3);
        try t.vm.quotation_literals.append(.{ .Quotation = q });
        q[0] = .{ .Word = t.vm.internSymbol("record-type-of") catch unreachable };
        q[1] = .{ .Symbol = name.Symbol };
        q[2] = .{ .Word = t.vm.internSymbol("eq?") catch unreachable };

        try t.vm.defineWord(predicate, .{ .Quotation = q });
    }

    {
        for (fields.Array) |sym, i| {
            const field_str = t.vm.symbol_table.items[sym.Symbol];

            const getter = try std.fmt.allocPrint(t.vm.allocator, "{}-{}", .{ name_str, field_str });
            defer t.vm.allocator.free(getter);
            const setter = try std.fmt.allocPrint(t.vm.allocator, "{}-{}!", .{ name_str, field_str });
            defer t.vm.allocator.free(setter);

            // TODO these should typecheck
            var q_get = try t.vm.allocator.alloc(Value, 3);
            try t.vm.quotation_literals.append(.{ .Quotation = q_get });
            q_get[0] = .{ .Int = @intCast(i64, i) };
            q_get[1] = .{ .Word = t.vm.internSymbol("swap") catch unreachable };
            q_get[2] = .{ .Word = t.vm.internSymbol("rget") catch unreachable };
            try t.vm.defineWord(getter, .{ .Quotation = q_get });

            var q_set = try t.vm.allocator.alloc(Value, 3);
            try t.vm.quotation_literals.append(.{ .Quotation = q_set });
            q_set[0] = .{ .Int = @intCast(i64, i) };
            q_set[1] = .{ .Word = t.vm.internSymbol("swap") catch unreachable };
            q_set[2] = .{ .Word = t.vm.internSymbol("rset!") catch unreachable };
            try t.vm.defineWord(setter, .{ .Quotation = q_set });
        }
    }
}

pub fn f_ref(t: *Thread) Thread.Error!void {
    const name = try t.stack.pop();
    if (name != .Symbol) return error.TypeError;

    if (t.vm.word_table.items[name.Symbol]) |val| {
        try t.stack.push(t.vm.dupValue(val));
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

// pub fn f_print_stack(t: *Thread) Thread.Error!void {
//     std.debug.print("STACK| len: {}\n", .{t.stack.data.items.len});
//     for (t.stack.data.items) |it, i| {
//         std.debug.print("  {}| ", .{t.stack.data.items.len - i - 1});
//         t.nicePrintValue(it);
//         std.debug.print("\n", .{});
//     }
// }

// display/write ===

fn displayValue(t: *Thread, value: Value) void {
    switch (value) {
        .Int => |val| std.debug.print("{}", .{val}),
        .Float => |val| std.debug.print("{d}f", .{val}),
        .Char => |val| switch (val) {
            '\n' => std.debug.print("#\\space", .{}),
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
        .Quotation => |q| {
            std.debug.print("{{ ", .{});
            for (q) |val| {
                displayValue(t, val);
                std.debug.print(" ", .{});
            }
            std.debug.print("}}", .{});
        },
        .Array => |a| {
            std.debug.print("{{ ", .{});
            for (a) |val| {
                displayValue(t, val);
                std.debug.print(" ", .{});
            }
            std.debug.print("}}a", .{});
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
    const id: VM.BuiltInIds = switch (val) {
        .Int => .Int,
        .Float => .Float,
        .Char => .Char,
        .Boolean => .Boolean,
        .Sentinel => .Sentinel,
        .String => .String,
        .Word => .Word,
        .Symbol => .Symbol,
        .Quotation => .Quotation,
        .Array => .Array,
        .FFI_Fn => .FFI_Fn,
        .FFI_Ptr => .FFI_Ptr,
    };
    try t.stack.push(.{ .Symbol = @enumToInt(id) });
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
        .Quotation => |val| val.ptr == b.Quotation.ptr and
            val.len == b.Quotation.len,
        .Array => |val| val.ptr == b.Array.ptr and
            val.len == b.Array.len,
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
        .Quotation => |val| blk: {
            for (val) |v, i| {
                if (!areValuesEquivalent(t, v, b.Quotation[i])) break :blk false;
            }
            break :blk true;
        },
        .Array => |val| blk: {
            for (val) |v, i| {
                if (!areValuesEquivalent(t, v, b.Array[i])) break :blk false;
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

// Rc ===

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

        rc.inc();
        try t.stack.push(.{
            .FFI_Ptr = .{
                .type_id = type_id,
                .ptr = @ptrCast(*FFI_Ptr.Ptr, rc),
            },
        });

        t.vm.dropValue(this);
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
        if (this != .FFI_Ptr and this != .String) return error.TypeError;
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

    pub const Record = struct {
        type_id: usize,
        slots: []Value,
    };

    var type_id: usize = undefined;

    pub fn install(vm: *VM) Allocator.Error!void {
        type_id = try vm.installType("record", .{
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
        const rc = ptr.cast(Rc(Record));
        std.debug.print("r< ", .{});
        for (rc.obj.slots) |v| {
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
            for (rc.obj.slots) |val| {
                vm.dropValue(val);
            }
            vm.allocator.free(rc.obj.slots);
            vm.allocator.destroy(rc);
        }
    }

    //;

    pub fn _make(t: *Thread) Thread.Error!void {
        const r_type = try t.stack.pop();
        if (r_type != .Int) return error.TypeError;

        const slot_ct = t.vm.type_table.items[@intCast(usize, r_type.Int)].ty.Record.slot_ct;

        var rc = try Rc(Record).makeOne(t.vm.allocator);
        rc.obj.type_id = @intCast(usize, r_type.Int);
        rc.obj.slots = try t.vm.allocator.alloc(Value, slot_ct);
        for (rc.obj.slots) |*v| {
            v.* = .{ .Boolean = false };
        }
        try t.stack.push(.{
            .FFI_Ptr = .{
                .type_id = type_id,
                .ptr = @ptrCast(*FFI_Ptr.Ptr, rc),
            },
        });
    }

    pub fn _set(t: *Thread) Thread.Error!void {
        const ptr = try t.stack.pop();
        const idx = try t.stack.pop();
        const val = try t.stack.pop();
        if (ptr != .FFI_Ptr) return error.TypeError;
        if (ptr.FFI_Ptr.type_id != type_id) return error.TypeError;
        if (idx != .Int) return error.TypeError;

        var rc = ptr.FFI_Ptr.cast(Rc(Record));
        rc.obj.slots[@intCast(usize, idx.Int)] = val;

        t.vm.dropValue(ptr);
    }

    pub fn _set_weak(t: *Thread) Thread.Error!void {
        // TODO
        //         const ptr = try t.stack.pop();
        //         const idx = try t.stack.pop();
        //         const val = try t.stack.pop();
        //         if (ptr != .FFI_Ptr) return error.TypeError;
        //         if (ptr.FFI_Ptr.type_id != type_id) return error.TypeError;
        //         if (idx != .Int) return error.TypeError;
        //
        //         var rc = ptr.FFI_Ptr.cast(Rc(Record));
        //         rc.obj.slots[@intCast(usize, idx.Int)] = val;
        //
        //         t.vm.dropValue(ptr);
    }

    pub fn _get(t: *Thread) Thread.Error!void {
        const ptr = try t.stack.pop();
        const idx = try t.stack.pop();
        if (ptr != .FFI_Ptr) return error.TypeError;
        if (ptr.FFI_Ptr.type_id != type_id) return error.TypeError;
        if (idx != .Int) return error.TypeError;

        var rc = ptr.FFI_Ptr.cast(Rc(Record));
        try t.stack.push(t.vm.dupValue(rc.obj.slots[@intCast(usize, idx.Int)]));

        t.vm.dropValue(ptr);
    }

    pub fn _type_of(t: *Thread) Thread.Error!void {
        const ptr = try t.stack.pop();
        if (ptr != .FFI_Ptr) return error.TypeError;
        if (ptr.FFI_Ptr.type_id != type_id) return error.TypeError;

        var rc = ptr.FFI_Ptr.cast(Rc(Record));
        try t.stack.push(.{ .Symbol = t.vm.type_table.items[rc.obj.type_id].name_id });

        t.vm.dropValue(ptr);
    }
};

// vec ===

// TODO vec insert, vec append
// non mutating versions of fns
pub const ft_vec = struct {
    const Self = @This();

    pub const Vec = ArrayList(Value);

    var type_id: usize = undefined;

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

    pub fn _to_quotation(t: *Thread) Thread.Error!void {
        // TODO
        //         const this = try t.stack.pop();
        //         switch (this) {
        //             .FFI_Ptr => |ptr| {
        //                 try Self.ffi_type.checkType(ptr);
        //                 var this_rc = ptr.cast(Rc(Vec));
        //                 if (this_rc.ref_ct == 1) {
        //                     try t.stack.push(.{ .FFI_Ptr = ft_quotation.ffi_type.makePtr(this_rc) });
        //                 } else {
        //                     var rc = try Rc(Vec).makeOne(t.vm.allocator);
        //                     rc.obj = Vec.init(t.vm.allocator);
        //                     try rc.obj.appendSlice(this_rc.obj.items);
        //                     try t.stack.push(.{ .FFI_Ptr = ft_quotation.ffi_type.makePtr(rc) });
        //                     t.vm.dropValue(this);
        //                 }
        //             },
        //             else => return error.TypeError,
        //         }
    }

    pub fn _push(t: *Thread) Thread.Error!void {
        const ptr = try t.stack.pop();
        const val = try t.stack.pop();
        if (ptr != .FFI_Ptr) return error.TypeError;
        if (ptr.FFI_Ptr.type_id != type_id) return error.TypeError;

        var rc = ptr.FFI_Ptr.cast(Rc(Vec));
        try rc.obj.append(val);

        t.vm.dropValue(ptr);
    }

    pub fn _set(t: *Thread) Thread.Error!void {
        const ptr = try t.stack.pop();
        const idx = try t.stack.pop();
        const val = try t.stack.pop();
        if (ptr != .FFI_Ptr) return error.TypeError;
        if (ptr.FFI_Ptr.type_id != type_id) return error.TypeError;
        if (idx != .Int) return error.TypeError;

        var rc = ptr.FFI_Ptr.cast(Rc(Vec));
        rc.obj.items[@intCast(usize, idx.Int)] = val;

        t.vm.dropValue(ptr);
    }

    pub fn _get(t: *Thread) Thread.Error!void {
        const ptr = try t.stack.pop();
        const idx = try t.stack.pop();
        if (ptr != .FFI_Ptr) return error.TypeError;
        if (ptr.FFI_Ptr.type_id != type_id) return error.TypeError;
        if (idx != .Int) return error.TypeError;

        var rc = ptr.FFI_Ptr.cast(Rc(Vec));
        try t.stack.push(t.vm.dupValue(rc.obj.items[@intCast(usize, idx.Int)]));

        t.vm.dropValue(ptr);
    }

    pub fn _len(t: *Thread) Thread.Error!void {
        const ptr = try t.stack.pop();
        if (ptr.FFI_Ptr.type_id != type_id) return error.TypeError;

        var rc = ptr.FFI_Ptr.cast(Rc(Vec));
        try t.stack.push(.{ .Int = @intCast(i32, rc.obj.items.len) });

        t.vm.dropValue(ptr);
    }

    pub fn _reverse_in_place(t: *Thread) Thread.Error!void {
        const ptr = try t.stack.pop();
        if (ptr != .FFI_Ptr) return error.TypeError;
        if (ptr.FFI_Ptr.type_id != type_id) return error.TypeError;

        var rc = ptr.FFI_Ptr.cast(Rc(Vec));
        std.mem.reverse(Value, rc.obj.items);

        t.vm.dropValue(ptr);
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
        // TODO
        //         std.debug.print("m[ ", .{});
        //         var iter = rc.obj.iterator();
        //         while (iter.next()) |entry| {
        //             std.debug.print("{} ", .{t.vm.symbol_table.items[entry.key]});
        //             t.nicePrintValue(entry.value);
        //             std.debug.print(" ", .{});
        //         }
        //         std.debug.print("]", .{});
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
            // TODO
            //             var iter = rc.obj.iterator();
            //             while (iter.next()) |entry| {
            //                 vm.dropValue(entry.value);
            //             }
            //             rc.obj.deinit();
            vm.allocator.destroy(rc);
        }
    }

    //;

    // should return a result
    pub fn _open(t: *Thread) Thread.Error!void {
        // TODO allow ffi string
        const path = try t.stack.pop();
        const open_flag_str = try t.stack.pop();
        if (path != .String) return error.TypeError;
        if (open_flag_str != .String) return error.TypeError;

        var flags = std.fs.File.OpenFlags{
            .read = false,
        };
        for (open_flag_str) |ch| {
            if (ch == 'r') flags.read = true;
            if (ch == 'w') flags.write = true;
        }

        if (std.fs.cwd().openFile(path.String, flags)) |f| {
            errdefer f.close();

            var rc = try Rc(File).makeOne(t.vm.allocator);
            rc.obj = f;
            try t.stack.push(.{
                .FFI_Ptr = .{
                    .type_id = type_id,
                    .ptr = @ptrCast(*FFI_Ptr.Ptr, rc),
                },
            });
            try t.stack.push(.{ .Boolean = true });
        } else {
            try t.stack.push(.{ .String = "couldn't load file" });
            try t.stack.push(.{ .Boolean = false });
        }
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
    .{ .name = "@record", .func = f_define_record_type },
    .{ .name = "ref", .func = f_ref },
    .{ .name = "eval'", .func = f_eval },
    .{ .name = "eval,restore'", .func = f_eval_restore },
    .{ .name = ">restore", .func = f_push_restore },

    .{ .name = "stack-len", .func = f_stack_len },
    .{ .name = "stack-index", .func = f_stack_index },
    .{ .name = "clear-stack", .func = f_clear_stack },

    // .{ .name = "_.stack", .func = f_print_stack },

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

    .{ .name = "<string>", .func = ft_string._make },
    .{ .name = "<string>,clone", .func = ft_string._clone },
    .{ .name = "string-append!", .func = ft_string._append_in_place },
    .{ .name = "string>symbol", .func = ft_string._to_symbol },
    .{ .name = "sget", .func = ft_string._get },
    .{ .name = "slen", .func = ft_string._len },

    // .{ .name = "quotation>vec", .func = ft_quotation._to_vec },

    .{ .name = "<record>", .func = ft_record._make },
    .{ .name = "record-type-of", .func = ft_record._type_of },
    .{ .name = "rset!", .func = ft_record._set },
    .{ .name = "rget", .func = ft_record._get },

    .{ .name = "<vec>", .func = ft_vec._make },
    .{ .name = "<vec>,capacity", .func = ft_vec._make_capacity },
    // .{ .name = "vec>quotation", .func = ft_vec._to_quotation },
    .{ .name = "vpush!", .func = ft_vec._push },
    .{ .name = "vset!", .func = ft_vec._set },
    .{ .name = "vget", .func = ft_vec._get },
    .{ .name = "vlen", .func = ft_vec._len },
    .{ .name = "vreverse!", .func = ft_vec._reverse_in_place },

    .{ .name = "<map>", .func = ft_map._make },
    .{ .name = "mget*", .func = ft_map._get },
    .{ .name = "mset!", .func = ft_map._set },
};
