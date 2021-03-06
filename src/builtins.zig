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

// TODO need
// move eqv fn for records into orth
// functions
//   text
//     string manipulation
//       substring
//     string format
//   thread exit
//   math stuff
//     handle integer overflow
//       check where it can happen and make it a Thread.Error or change + to +%
//   short circuiting and and or
//   subslice, first rest

// TODO want
// def vs def_clobber, def doesnt clobber
// try using the return stack for eval,restore
// more ways to print vm info
//   word table
// ports
//   string, vector port
//   write an iterator to a port
// all returns of error.TypeError report what was expected
// dont use zig stack for recursion
//   zig value iterator that can iterate over slices
//     if iterating over a non slice value, just return that value once then return null
//     for display and write
// rename record to array ?
//   could give them a resize fn
//     could write vecs in orth
// functions
//   text
//     printing functions
//       write
//         need to translate '\n' in strings to a "\n"
//   math
//     fract
//     dont type check, have separte functions for ints and floats ?
//       general versions of fns like + can be written in orth that typecheck
// homogeneous vector thing
//   []i64, []f64 etc

//;

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
    try t.evaluateValue(null, val, 0);
}

pub fn f_eval_restore(t: *Thread) Thread.Error!void {
    const restore_num = try t.stack.pop();
    const val = try t.stack.pop();
    if (restore_num != .Int) return error.TypeError;

    const restore_u = @intCast(usize, restore_num.Int);

    var i: usize = 0;
    while (i < restore_u) : (i += 1) {
        try t.restore_stack.push(try t.stack.pop());
    }
    try t.evaluateValue(null, val, restore_u);
}

pub fn f_nop(t: *Thread) Thread.Error!void {}

pub fn f_panic(t: *Thread) Thread.Error!void {
    return error.Panic;
}

pub fn f_type_error(t: *Thread) Thread.Error!void {
    return error.TypeError;
}

pub fn f_stack_len(t: *Thread) Thread.Error!void {
    try t.stack.push(.{ .Int = @intCast(i64, t.stack.data.items.len) });
}

pub fn f_stack_index(t: *Thread) Thread.Error!void {
    const idx = try t.stack.pop();
    if (idx != .Int) return error.TypeError;
    try t.stack.push(t.vm.dupValue((try t.stack.index(@intCast(usize, idx.Int))).*));
}

pub fn f_stack_clear(t: *Thread) Thread.Error!void {
    for (t.stack.data.items) |v| {
        t.vm.dropValue(v);
    }
    t.stack.data.items.len = 0;
}

// pub fn f_print_rstack(t: *Thread) Thread.Error!void {
//     const len = t.return_stack.data.items.len;
//     std.debug.print("RSTACK| len: {}\n", .{len});
//     for (t.return_stack.data.items) |it, i| {
//         std.debug.print("  {}| ", .{len - i - 1});
//         t.nicePrintValue(it.value);
//         if (it.restore_ct == std.math.maxInt(usize)) {
//             std.debug.print(" :: max\n", .{});
//         } else {
//             std.debug.print(" :: {}\n", .{it.restore_ct});
//         }
//     }
// }
//
// pub fn f_print_current(t: *Thread) Thread.Error!void {
//     std.debug.print("CURRENT EXEC: {}| {{", .{t.restore_ct});
//     for (t.current_execution) |val| {
//         t.nicePrintValue(val);
//     }
//     std.debug.print("}}\n", .{});
// }

// display/write ===

fn writerDisplayValue(writer: anytype, t: *Thread, value: Value) !void {
    switch (value) {
        .Int => |val| try std.fmt.format(writer, "{}", .{val}),
        .Float => |val| try std.fmt.format(writer, "{d}f", .{val}),
        .Char => |val| try std.fmt.format(writer, "{c}", .{val}),
        .Boolean => |val| {
            const str = if (val) "#t" else "#f";
            try std.fmt.format(writer, "{s}", .{str});
        },
        .Sentinel => try std.fmt.format(writer, "#sentinel", .{}),
        .Symbol => |val| try std.fmt.format(writer, ":{}", .{t.vm.symbol_table.items[val]}),
        .Word => |val| try std.fmt.format(writer, "{}", .{t.vm.symbol_table.items[val]}),
        .String => |val| try std.fmt.format(writer, "{}", .{val}),
        .Slice => |slc| {
            try std.fmt.format(writer, "{{ ", .{});
            for (slc) |val| {
                // TODO
                writerDisplayValue(writer, t, val) catch unreachable;
                try std.fmt.format(writer, " ", .{});
            }
            try std.fmt.format(writer, "}}", .{});
        },
        .FFI_Fn => |val| try std.fmt.format(writer, "fn({})", .{t.vm.symbol_table.items[val.name_id]}),
        .RcPtr => |ptr| {
            const name_id = t.vm.type_table.items[ptr.rc.type_id].name_id;
            if (ptr.is_weak) {
                try std.fmt.format(writer, "rc@({} {})W", .{
                    t.vm.symbol_table.items[name_id],
                    @ptrToInt(ptr.rc.ptr),
                });
            } else {
                try std.fmt.format(writer, "rc@({} {})", .{
                    t.vm.symbol_table.items[name_id],
                    @ptrToInt(ptr.rc.ptr),
                });
            }
        },
        .UnmanagedPtr => |ptr| {
            const name_id = t.vm.type_table.items[ptr.type_id].name_id;
            try std.fmt.format(writer, "ffi@({} {})", .{
                t.vm.symbol_table.items[name_id],
                @ptrToInt(ptr.ptr),
            });
        },
    }
}

fn writerWriteValue(writer: anytype, t: *Thread, value: Value) !void {
    switch (value) {
        .Int => |val| try std.fmt.format(writer, "{}", .{val}),
        .Float => |val| try std.fmt.format(writer, "{d}", .{val}),
        .Char => |val| switch (val) {
            ' ' => try std.fmt.format(writer, "#\\space", .{}),
            '\n' => try std.fmt.format(writer, "#\\newline", .{}),
            '\t' => try std.fmt.format(writer, "#\\tab", .{}),
            else => try std.fmt.format(writer, "#\\{c}", .{val}),
        },
        .Boolean => |val| {
            const str = if (val) "#t" else "#f";
            try std.fmt.format(writer, "{s}", .{str});
        },
        .Sentinel => try std.fmt.format(writer, "#sentinel", .{}),
        .Symbol => |val| try std.fmt.format(writer, ":{}", .{t.vm.symbol_table.items[val]}),
        .Word => |val| try std.fmt.format(writer, "{}", .{t.vm.symbol_table.items[val]}),
        // TODO have to convert escapes in strings
        .String => |val| try std.fmt.format(writer, "\"{}\"", .{val}),
        .Slice => |slc| {
            try std.fmt.format(writer, "{{ ", .{});
            for (slc) |val| {
                // TODO
                writerWriteValue(writer, t, val) catch unreachable;
                try std.fmt.format(writer, " ", .{});
            }
            try std.fmt.format(writer, "}}", .{});
        },
        .FFI_Fn => |val| try std.fmt.format(writer, "{}", .{t.vm.symbol_table.items[val.name_id]}),
        .RcPtr => |ptr| {
            // TODO what to do here
            const name_id = t.vm.type_table.items[ptr.rc.type_id].name_id;
            if (ptr.is_weak) {
                try std.fmt.format(writer, "rc@({} {})W", .{
                    t.vm.symbol_table.items[name_id],
                    @ptrToInt(ptr.rc.ptr),
                });
            } else {
                try std.fmt.format(writer, "rc@({} {})", .{
                    t.vm.symbol_table.items[name_id],
                    @ptrToInt(ptr.rc.ptr),
                });
            }
        },
        .UnmanagedPtr => |ptr| {
            // TODO what to do here
            const name_id = t.vm.type_table.items[ptr.type_id].name_id;
            try std.fmt.format(writer, "ffi@({} {})", .{
                t.vm.symbol_table.items[name_id],
                @ptrToInt(ptr.ptr),
            });
        },
    }
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
    // try t.evaluateValue(.{ .UnmanagedPtr = ft_quotation.ffi_type.makePtr(rc.ref()) }, 0);
}

// built in types ===

pub fn f_value_type_of(t: *Thread) Thread.Error!void {
    const val = try t.stack.pop();
    try t.stack.push(.{ .Symbol = @enumToInt(@as(ValueType, val)) });
    t.vm.dropValue(val);
}

pub fn f_rc_type_of(t: *Thread) Thread.Error!void {
    const val = try t.stack.pop();
    if (val != .RcPtr) return error.TypeError;
    try t.stack.push(.{ .Symbol = t.vm.type_table.items[val.RcPtr.rc.type_id].name_id });
    t.vm.dropValue(val);
}

pub fn f_unmanaged_type_of(t: *Thread) Thread.Error!void {
    const val = try t.stack.pop();
    if (val != .UnmanagedPtr) return error.TypeError;
    try t.stack.push(.{ .Symbol = t.vm.type_table.items[val.UnmanagedPtr.type_id].name_id });
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

// chars ===

pub fn f_char_to_int(t: *Thread) Thread.Error!void {
    const ch = try t.stack.pop();
    if (ch != .Char) return error.TypeError;
    try t.stack.push(.{ .Int = ch.Char });
}

pub fn f_int_to_char(t: *Thread) Thread.Error!void {
    const i = try t.stack.pop();
    if (i != .Int) return error.TypeError;
    try t.stack.push(.{ .Char = @intCast(u8, i.Int) });
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
        .FFI_Fn => |ptr| ptr.name_id == b.FFI_Fn.name_id and
            ptr.func == b.FFI_Fn.func,
        .RcPtr => |ptr| ptr.rc == b.RcPtr.rc and
            ptr.is_weak == b.RcPtr.is_weak,
        .UnmanagedPtr => |ptr| ptr.type_id == b.UnmanagedPtr.type_id and
            ptr.ptr == b.UnmanagedPtr.ptr,
    } else false;
}

pub fn f_equal(t: *Thread) Thread.Error!void {
    const a = try t.stack.pop();
    const b = try t.stack.pop();
    try t.stack.push(.{ .Boolean = areValuesEqual(a, b) });
    t.vm.dropValue(a);
    t.vm.dropValue(b);
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
        // TODO dont use the zig stack
        .Slice => |val| blk: {
            for (val) |v, i| {
                if (!areValuesEquivalent(t, v, b.Slice[i])) break :blk false;
            }
            break :blk true;
        },
        .RcPtr => |ptr| t.vm.type_table.items[ptr.rc.type_id].ty.Rc.equivalent_fn(t, ptr, b),
        .UnmanagedPtr => |ptr| t.vm.type_table.items[ptr.type_id].ty.Unmanaged.equivalent_fn(t, ptr, b),
    } else blk: {
        // TODO
        break :blk false;
    };
}

pub fn f_equivalent(t: *Thread) Thread.Error!void {
    const a = try t.stack.pop();
    const b = try t.stack.pop();
    try t.stack.push(.{ .Boolean = areValuesEquivalent(t, a, b) });
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

pub fn f_slice_to_vec(t: *Thread) Thread.Error!void {
    const slc = try t.stack.pop();
    if (slc != .Slice) return error.TypeError;

    var clone = try t.vm.allocator.dupe(Value, slc.Slice);
    var vec = try t.vm.allocator.create(ft_vec.Vec);
    vec.* = ft_vec.Vec.fromOwnedSlice(t.vm.allocator, clone);
    var rc = try Rc.makeOne(t.vm.allocator, ft_vec.type_id, vec);
    try t.stack.push(.{
        .RcPtr = .{
            .rc = rc,
            .is_weak = false,
        },
    });
}

// rc ===

pub fn f_is_weak(t: *Thread) Thread.Error!void {
    const this = try t.stack.pop();
    if (this != .RcPtr) return error.TypeError;
    try t.stack.push(.{ .Boolean = this.RcPtr.is_weak });
    t.vm.dropValue(this);
}

pub fn f_downgrade(t: *Thread) Thread.Error!void {
    const this = try t.stack.index(0);
    if (this.* != .RcPtr) return error.TypeError;
    var ptr = &this.*.RcPtr;
    const ref_ct = ptr.rc.ref_ct;
    t.vm.dropValue(this.*);
    if (ref_ct == 1) {
        _ = t.stack.pop() catch unreachable;
        try t.stack.push(.{ .Boolean = false });
        try t.stack.push(.{ .Boolean = false });
    } else {
        ptr.is_weak = true;
        try t.stack.push(.{ .Boolean = true });
    }
}

pub fn f_upgrade(t: *Thread) Thread.Error!void {
    const this = try t.stack.index(0);
    if (this.* != .RcPtr) return error.TypeError;
    var ptr = &this.*.RcPtr;
    ptr.is_weak = false;
    ptr.rc.inc();
}

// record ===

pub const ft_record = struct {
    const Self = @This();

    pub const Record = []Value;

    var type_id: usize = undefined;

    pub fn install(vm: *VM) Allocator.Error!void {
        type_id = try vm.installType("record", .{
            .ty = .{
                .Rc = .{
                    .finalize_fn = finalize,
                },
            },
        });
    }

    pub fn finalize(vm: *VM, ptr: RcPtr) void {
        var rec = ptr.rc.cast(Record);
        for (rec.*) |val| {
            vm.dropValue(val);
        }
        vm.allocator.free(rec.*);
        vm.allocator.destroy(rec);
    }

    //;

    pub fn _make(t: *Thread) Thread.Error!void {
        const slot_ct = try t.stack.pop();
        if (slot_ct != .Int) return error.TypeError;

        var rec = try t.vm.allocator.create(Record);
        var data = try t.vm.allocator.alloc(Value, @intCast(usize, slot_ct.Int));
        for (data) |*v| {
            v.* = .{ .Sentinel = {} };
        }
        rec.* = data;

        var rc = try Rc.makeOne(t.vm.allocator, type_id, rec);
        try t.stack.push(.{
            .RcPtr = .{
                .rc = rc,
                .is_weak = false,
            },
        });
    }

    pub fn _clone(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        if (this != .RcPtr) return error.TypeError;
        if (this.RcPtr.rc.type_id != type_id) return error.TypeError;

        var this_data = this.RcPtr.rc.cast(Record);

        var rec = try t.vm.allocator.create(Record);
        var data = try t.vm.allocator.alloc(Value, @intCast(usize, this_data.len));
        for (data) |*v, i| {
            v.* = t.vm.dupValue(this_data.*[i]);
        }
        rec.* = data;

        var rc = try Rc.makeOne(t.vm.allocator, type_id, rec);
        try t.stack.push(.{
            .RcPtr = .{
                .rc = rc,
                .is_weak = false,
            },
        });
    }

    pub fn _set(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const idx = try t.stack.pop();
        const val = try t.stack.pop();
        if (this != .RcPtr) return error.TypeError;
        if (this.RcPtr.rc.type_id != type_id) return error.TypeError;
        if (idx != .Int) return error.TypeError;

        var rec = this.RcPtr.rc.cast(Record);
        rec.*[@intCast(usize, idx.Int)] = val;

        t.vm.dropValue(this);
    }

    pub fn _get(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const idx = try t.stack.pop();
        if (this != .RcPtr) return error.TypeError;
        if (this.RcPtr.rc.type_id != type_id) return error.TypeError;
        if (idx != .Int) return error.TypeError;

        var rec = this.RcPtr.rc.cast(Record);
        try t.stack.push(t.vm.dupValue(rec.*[@intCast(usize, idx.Int)]));

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

    pub fn install(vm: *VM) Allocator.Error!void {
        type_id = try vm.installType("vec", .{
            .ty = .{
                .Rc = .{
                    .finalize_fn = finalize,
                },
            },
        });
    }

    pub fn finalize(vm: *VM, ptr: RcPtr) void {
        var vec = ptr.rc.cast(Vec);
        for (vec.items) |val| {
            vm.dropValue(val);
        }
        vec.deinit();
        vm.allocator.destroy(vec);
    }

    //;

    pub fn _make(t: *Thread) Thread.Error!void {
        var vec = try t.vm.allocator.create(Vec);
        vec.* = Vec.init(t.vm.allocator);
        var rc = try Rc.makeOne(t.vm.allocator, type_id, vec);
        try t.stack.push(.{
            .RcPtr = .{
                .rc = rc,
                .is_weak = false,
            },
        });
    }

    pub fn _make_capacity(t: *Thread) Thread.Error!void {
        const capacity = try t.stack.pop();
        if (capacity != .Int) return error.TypeError;

        var vec = try t.vm.allocator.create(Vec);
        vec.* = try Vec.initCapacity(
            t.vm.allocator,
            @intCast(usize, capacity.Int),
        );
        var rc = try Rc.makeOne(t.vm.allocator, type_id, vec);
        try t.stack.push(.{
            .RcPtr = .{
                .rc = rc,
                .is_weak = false,
            },
        });
    }

    pub fn _to_slice(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        if (this != .RcPtr) return error.TypeError;
        if (this.RcPtr.rc.type_id != type_id) return error.TypeError;

        var vec = this.RcPtr.rc.cast(Vec);
        const slc = try t.vm.allocator.dupe(Value, vec.items);
        try t.vm.slice_literals.append(.{ .Slice = slc });
        try t.stack.push(.{ .Slice = slc });

        t.vm.dropValue(this);
    }

    pub fn _push(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const val = try t.stack.pop();
        if (this != .RcPtr) return error.TypeError;
        if (this.RcPtr.rc.type_id != type_id) return error.TypeError;

        var vec = this.RcPtr.rc.cast(Vec);
        try vec.append(val);

        t.vm.dropValue(this);
    }

    pub fn _pop(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        if (this != .RcPtr) return error.TypeError;
        if (this.RcPtr.rc.type_id != type_id) return error.TypeError;

        var vec = this.RcPtr.rc.cast(Vec);
        // TODO error if vec.items.len == 0
        const popped = vec.items[vec.items.len - 1];
        vec.items.len -= 1;
        try t.stack.push(popped);

        t.vm.dropValue(this);
    }

    pub fn _set(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const idx = try t.stack.pop();
        const val = try t.stack.pop();
        if (this != .RcPtr) return error.TypeError;
        if (this.RcPtr.rc.type_id != type_id) return error.TypeError;
        if (idx != .Int) return error.TypeError;

        var vec = this.RcPtr.rc.cast(Vec);
        t.vm.dropValue(vec.items[@intCast(usize, idx.Int)]);
        vec.items[@intCast(usize, idx.Int)] = val;

        t.vm.dropValue(this);
    }

    pub fn _get(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const idx = try t.stack.pop();
        if (this != .RcPtr) return error.TypeError;
        if (this.RcPtr.rc.type_id != type_id) return error.TypeError;
        if (idx != .Int) return error.TypeError;

        var vec = this.RcPtr.rc.cast(Vec);
        try t.stack.push(t.vm.dupValue(vec.items[@intCast(usize, idx.Int)]));

        t.vm.dropValue(this);
    }

    pub fn _len(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        if (this != .RcPtr) return error.TypeError;
        if (this.RcPtr.rc.type_id != type_id) return error.TypeError;

        var vec = this.RcPtr.rc.cast(Vec);
        try t.stack.push(.{ .Int = @intCast(i32, vec.items.len) });

        t.vm.dropValue(this);
    }

    pub fn _reverse_in_place(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        if (this != .RcPtr) return error.TypeError;
        if (this.RcPtr.rc.type_id != type_id) return error.TypeError;

        var vec = this.RcPtr.rc.cast(Vec);
        std.mem.reverse(Value, vec.items);

        t.vm.dropValue(this);
    }
};

// string ===

// TODO separate out code that takes a literal string
pub const ft_string = struct {
    const Self = @This();

    pub const String = ArrayList(u8);

    var type_id: usize = undefined;

    pub fn install(vm: *VM) Allocator.Error!void {
        type_id = try vm.installType("string", .{
            .ty = .{
                .Rc = .{
                    .finalize_fn = finalize,
                },
            },
        });
    }

    pub fn finalize(vm: *VM, ptr: RcPtr) void {
        var string = ptr.rc.cast(String);
        string.deinit();
        vm.allocator.destroy(string);
    }

    //;

    fn makeRcFromSlice(allocator: *Allocator, slice: []const u8) Allocator.Error!*Rc {
        var string = try allocator.create(String);
        string.* = String.init(allocator);
        try string.appendSlice(slice);
        var rc = try Rc.makeOne(allocator, type_id, string);
        return rc;
    }

    fn makeRcMoveSlice(allocator: *Allocator, slice: []u8) Allocator.Error!*Rc {
        var string = try allocator.create(String);
        string.* = String.fromOwnedSlice(allocator, slice);
        var rc = try Rc.makeOne(allocator, type_id, string);
        return rc;
    }

    pub fn _make(t: *Thread) Thread.Error!void {
        var string = try t.vm.allocator.create(String);
        string.* = String.init(t.vm.allocator);
        var rc = try Rc.makeOne(t.vm.allocator, type_id, string);
        try t.stack.push(.{
            .RcPtr = .{
                .rc = rc,
                .is_weak = false,
            },
        });
    }

    pub fn _clone(t: *Thread) Thread.Error!void {
        const other = try t.stack.pop();
        switch (other) {
            .String => |str| {
                var rc = try makeRcFromSlice(t.vm.allocator, str);
                try t.stack.push(.{
                    .RcPtr = .{
                        .rc = rc,
                        .is_weak = false,
                    },
                });
            },
            .RcPtr => |ptr| {
                if (ptr.rc.type_id != type_id) return error.TypeError;

                var other_str = ptr.rc.cast(String);
                var rc = try makeRcFromSlice(t.vm.allocator, other_str.items);

                try t.stack.push(.{
                    .RcPtr = .{
                        .rc = rc,
                        .is_weak = false,
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
        switch (this) {
            .String => {},
            .RcPtr => |ptr| if (ptr.rc.type_id != type_id) return error.TypeError,
            else => return error.TypeError,
        }
        switch (other) {
            .String => {},
            .RcPtr => |ptr| if (ptr.rc.type_id != type_id) return error.TypeError,
            else => return error.TypeError,
        }

        const rc = switch (this) {
            .String => |str| try makeRcFromSlice(t.vm.allocator, str),
            .RcPtr => |ptr| ptr.rc,
            else => unreachable,
        };

        const o_str = switch (other) {
            .String => |str| str,
            .RcPtr => |ptr| ptr.rc.cast(String).items,
            else => unreachable,
        };

        try rc.cast(String).appendSlice(o_str);

        try t.stack.push(.{
            .RcPtr = .{
                .rc = rc,
                .is_weak = false,
            },
        });

        t.vm.dropValue(other);
    }

    pub fn _to_symbol(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        switch (this) {
            .String => {},
            .RcPtr => |ptr| if (ptr.rc.type_id != type_id) return error.TypeError,
            else => return error.TypeError,
        }

        const str = switch (this) {
            .String => |str| str,
            .RcPtr => |ptr| ptr.rc.cast(String).items,
            else => unreachable,
        };

        try t.stack.push(.{ .Symbol = try t.vm.internSymbol(str) });

        t.vm.dropValue(this);
    }

    pub fn _to_vec(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        switch (this) {
            .String => {},
            .RcPtr => |ptr| if (ptr.rc.type_id != type_id) return error.TypeError,
            else => return error.TypeError,
        }

        const str = switch (this) {
            .String => |str| str,
            .RcPtr => |ptr| ptr.rc.cast(String).items,
            else => unreachable,
        };

        var vec = try t.vm.allocator.create(ft_vec.Vec);
        vec.* = try ft_vec.Vec.initCapacity(t.vm.allocator, str.len);
        for (str) |ch| {
            vec.append(.{ .Char = ch }) catch unreachable;
        }
        var rc = try Rc.makeOne(t.vm.allocator, ft_vec.type_id, vec);
        try t.stack.push(.{
            .RcPtr = .{
                .rc = rc,
                .is_weak = false,
            },
        });

        t.vm.dropValue(this);
    }

    pub fn _get(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const idx = try t.stack.pop();
        switch (this) {
            .String => {},
            .RcPtr => |ptr| if (ptr.rc.type_id != type_id) return error.TypeError,
            else => return error.TypeError,
        }
        if (idx != .Int) return error.TypeError;

        const str = switch (this) {
            .String => |str| str,
            .RcPtr => |ptr| ptr.rc.cast(String).items,
            else => unreachable,
        };

        try t.stack.push(.{ .Char = str[@intCast(usize, idx.Int)] });

        t.vm.dropValue(this);
    }

    pub fn _len(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        switch (this) {
            .String => {},
            .RcPtr => |ptr| if (ptr.rc.type_id != type_id) return error.TypeError,
            else => return error.TypeError,
        }

        const str = switch (this) {
            .String => |str| str,
            .RcPtr => |ptr| ptr.rc.cast(String).items,
            else => unreachable,
        };

        try t.stack.push(.{ .Int = @intCast(i32, str.len) });

        t.vm.dropValue(this);
    }
};

// map ===

pub const ft_map = struct {
    const Self = @This();

    pub const Map = std.AutoHashMap(usize, Value);

    pub var type_id: usize = undefined;

    pub fn install(vm: *VM) Allocator.Error!void {
        type_id = try vm.installType("map", .{
            .ty = .{
                .Rc = .{
                    .finalize_fn = finalize,
                },
            },
        });
    }

    pub fn finalize(vm: *VM, ptr: RcPtr) void {
        var map = ptr.rc.cast(Map);
        var iter = map.iterator();
        while (iter.next()) |entry| {
            vm.dropValue(entry.value);
        }
        map.deinit();
        vm.allocator.destroy(map);
    }

    //;

    pub fn _make(t: *Thread) Thread.Error!void {
        var map = try t.vm.allocator.create(Map);
        map.* = Map.init(t.vm.allocator);
        var rc = try Rc.makeOne(t.vm.allocator, type_id, map);
        try t.stack.push(.{
            .RcPtr = .{
                .rc = rc,
                .is_weak = false,
            },
        });
    }

    pub fn _set(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const sym = try t.stack.pop();
        const value = try t.stack.pop();
        if (this != .RcPtr) return error.TypeError;
        if (this.RcPtr.rc.type_id != type_id) return error.TypeError;
        if (sym != .Symbol) return error.TypeError;

        var map = this.RcPtr.rc.cast(Map);

        // TODO handle overwrite
        try map.put(sym.Symbol, value);

        t.vm.dropValue(this);
    }

    pub fn _get(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const sym = try t.stack.pop();
        if (this != .RcPtr) return error.TypeError;
        if (this.RcPtr.rc.type_id != type_id) return error.TypeError;
        if (sym != .Symbol) return error.TypeError;

        var map = this.RcPtr.rc.cast(Map);

        if (map.get(sym.Symbol)) |val| {
            try t.stack.push(t.vm.dupValue(val));
            try t.stack.push(.{ .Boolean = true });
        } else {
            try t.stack.push(.{ .String = "not found" });
            try t.stack.push(.{ .Boolean = false });
        }

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
                .Rc = .{
                    .finalize_fn = finalize,
                },
            },
        });
    }

    pub fn finalize(vm: *VM, ptr: RcPtr) void {
        var file = ptr.rc.cast(File);
        vm.allocator.free(file.filepath);
        file.file.close();
        vm.allocator.destroy(file);
    }

    //;

    // TODO
    //   file close
    //   read until delimiter
    //   write until delimiter

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

        var file = try t.vm.allocator.create(File);
        file.* = .{
            .filepath = try t.vm.allocator.dupe(u8, path.String),
            .file = f,
        };

        var rc = try Rc.makeOne(t.vm.allocator, type_id, file);
        try t.stack.push(.{
            .RcPtr = .{
                .rc = rc,
                .is_weak = false,
            },
        });
        try t.stack.push(.{ .Boolean = true });
    }

    // TODO there could be an error if <file>,std is called more than once
    //   and orth tries to close one of the files twice
    pub fn _std(t: *Thread) Thread.Error!void {
        const which = try t.stack.pop();
        if (which != .Symbol) return error.TypeError;

        var fp: []const u8 = undefined;
        var f: std.fs.File = undefined;
        if (which.Symbol == try t.vm.internSymbol("in")) {
            fp = "stdin";
            f = std.io.getStdIn();
        } else if (which.Symbol == try t.vm.internSymbol("out")) {
            fp = "stdout";
            f = std.io.getStdOut();
        } else if (which.Symbol == try t.vm.internSymbol("err")) {
            fp = "stderr";
            f = std.io.getStdErr();
        } else {
            // TODO
            try t.stack.push(.{ .Boolean = false });
            try t.stack.push(.{ .Boolean = false });
            return;
        }

        var file = try t.vm.allocator.create(File);
        file.* = .{
            .filepath = try t.vm.allocator.dupe(u8, fp),
            .file = f,
        };

        var rc = try Rc.makeOne(t.vm.allocator, type_id, file);
        try t.stack.push(.{
            .RcPtr = .{
                .rc = rc,
                .is_weak = false,
            },
        });
        try t.stack.push(.{ .Boolean = true });
    }

    pub fn _filepath(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        if (this != .RcPtr) return error.TypeError;
        if (this.RcPtr.rc.type_id != type_id) return error.TypeError;

        const file = this.RcPtr.rc.cast(File);
        var rc_str = try ft_string.makeRcFromSlice(t.vm.allocator, file.filepath);
        try t.stack.push(.{
            .RcPtr = .{
                .rc = rc_str,
                .is_weak = false,
            },
        });

        t.vm.dropValue(this);
    }

    // TODO could use eof object instead of result type
    pub fn _read_char(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        if (this != .RcPtr) return error.TypeError;
        if (this.RcPtr.rc.type_id != type_id) return error.TypeError;

        var file = this.RcPtr.rc.cast(File);
        var buf = [1]u8{undefined};
        // TODO handle read errors
        const ct = file.file.read(&buf) catch unreachable;
        if (ct == 0) {
            try t.stack.push(.{ .Boolean = false });
            try t.stack.push(.{ .Boolean = false });
        } else {
            try t.stack.push(.{ .Char = buf[0] });
            try t.stack.push(.{ .Boolean = true });
        }
        t.vm.dropValue(this);
    }

    pub fn _peek_char(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        if (this != .RcPtr) return error.TypeError;
        if (this.RcPtr.rc.type_id != type_id) return error.TypeError;

        var file = this.RcPtr.rc.cast(File);
        var buf = [1]u8{undefined};
        // TODO handle read errors
        const ct = file.file.read(&buf) catch unreachable;
        if (ct == 0) {
            try t.stack.push(.{ .Boolean = false });
            try t.stack.push(.{ .Boolean = false });
        } else {
            file.file.seekBy(-@intCast(i64, ct)) catch unreachable;
            try t.stack.push(.{ .Char = buf[0] });
            try t.stack.push(.{ .Boolean = true });
        }
        t.vm.dropValue(this);
    }

    pub fn _read_delimiter(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const delim = try t.stack.pop();
        if (this != .RcPtr) return error.TypeError;
        if (this.RcPtr.rc.type_id != type_id) return error.TypeError;
        if (delim != .Char) return error.TypeError;

        var file = this.RcPtr.rc.cast(File);
        var reader = file.file.reader();

        const buf = reader.readUntilDelimiterAlloc(
            t.vm.allocator,
            delim.Char,
            std.math.maxInt(usize),
        ) catch |err| {
            switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => unreachable,
            }
        };

        var rc_str = try ft_string.makeRcMoveSlice(t.vm.allocator, buf);
        try t.stack.push(.{
            .RcPtr = .{
                .rc = rc_str,
                .is_weak = false,
            },
        });
        try t.stack.push(.{ .Boolean = true });

        t.vm.dropValue(this);
    }

    pub fn _read_all(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        if (this != .RcPtr) return error.TypeError;
        if (this.RcPtr.rc.type_id != type_id) return error.TypeError;

        var file = this.RcPtr.rc.cast(File);
        // TODO
        file.file.seekTo(0) catch unreachable;
        const buf = file.file.readToEndAlloc(
            t.vm.allocator,
            std.math.maxInt(usize),
        ) catch |err| {
            switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => unreachable,
            }
        };

        var rc_str = try ft_string.makeRcMoveSlice(t.vm.allocator, buf);
        try t.stack.push(.{
            .RcPtr = .{
                .rc = rc_str,
                .is_weak = false,
            },
        });
        try t.stack.push(.{ .Boolean = true });

        t.vm.dropValue(this);
    }

    pub fn _display(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const val = try t.stack.pop();
        if (this != .RcPtr) return error.TypeError;
        if (this.RcPtr.rc.type_id != type_id) return error.TypeError;

        var file = this.RcPtr.rc.cast(File);
        writerDisplayValue(file.file.writer(), t, val) catch unreachable;

        t.vm.dropValue(this);
        t.vm.dropValue(val);
    }

    pub fn _write(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const val = try t.stack.pop();
        if (this != .RcPtr) return error.TypeError;
        if (this.RcPtr.rc.type_id != type_id) return error.TypeError;

        var file = this.RcPtr.rc.cast(File);
        writerWriteValue(file.file.writer(), t, val) catch unreachable;

        t.vm.dropValue(this);
        t.vm.dropValue(val);
    }

    pub fn _write_char(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const ch = try t.stack.pop();
        if (this != .RcPtr) return error.TypeError;
        if (this.RcPtr.rc.type_id != type_id) return error.TypeError;
        if (ch != .Char) return error.TypeError;

        const buf = [1]u8{ch.Char};

        var file = this.RcPtr.rc.cast(File);
        // TODO
        file.file.writeAll(&buf) catch unreachable;

        t.vm.dropValue(this);
    }

    pub fn _write_all(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const str = try t.stack.pop();
        if (this != .RcPtr) return error.TypeError;
        if (this.RcPtr.rc.type_id != type_id) return error.TypeError;
        // TODO take ffi string
        if (str != .String) return error.TypeError;

        var file = this.RcPtr.rc.cast(File);
        // TODO
        file.file.writeAll(str.String) catch unreachable;

        t.vm.dropValue(this);
    }
};

// =====

const BuiltinDefinition = struct {
    name: []const u8,
    func: FFI_Fn.Function,
};

pub const builtins = [_]BuiltinDefinition{
    .{ .name = "def", .func = f_def },
    .{ .name = "ref", .func = f_ref },
    .{ .name = "eval'", .func = f_eval },
    .{ .name = "eval,restore'", .func = f_eval_restore },

    .{ .name = "nop", .func = f_nop },
    .{ .name = "panic", .func = f_panic },
    .{ .name = "type-error", .func = f_type_error },

    .{ .name = "stack.len", .func = f_stack_len },
    .{ .name = "stack.index", .func = f_stack_index },
    .{ .name = "stack.clear!", .func = f_stack_clear },

    // .{ .name = ".rstack'", .func = f_print_rstack },
    // .{ .name = ".current'", .func = f_print_current },

    .{ .name = "read", .func = f_read },
    .{ .name = "parse", .func = f_parse },

    .{ .name = "value-type-of", .func = f_value_type_of },
    .{ .name = "rc-type-of", .func = f_rc_type_of },
    .{ .name = "unmanaged-type-of", .func = f_unmanaged_type_of },
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

    .{ .name = "char>int", .func = f_char_to_int },
    .{ .name = "int>char", .func = f_int_to_char },

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
    .{ .name = "slice>vec", .func = f_slice_to_vec },

    .{ .name = "rc-ptr.weak?", .func = f_is_weak },
    .{ .name = "downgrade", .func = f_downgrade },
    .{ .name = "upgrade", .func = f_upgrade },

    .{ .name = "<record>", .func = ft_record._make },
    .{ .name = "<record>,clone", .func = ft_record._clone },
    .{ .name = "rset!", .func = ft_record._set },
    .{ .name = "rget", .func = ft_record._get },

    .{ .name = "<vec>", .func = ft_vec._make },
    .{ .name = "<vec>,capacity", .func = ft_vec._make_capacity },
    .{ .name = "vec>slice", .func = ft_vec._to_slice },
    // TODO
    // .{ .name = "vec>string", .func = ft_vec._to_string },
    .{ .name = "vpush!", .func = ft_vec._push },
    .{ .name = "vpop!", .func = ft_vec._pop },
    .{ .name = "vset!", .func = ft_vec._set },
    .{ .name = "vget", .func = ft_vec._get },
    .{ .name = "vlen", .func = ft_vec._len },
    .{ .name = "vreverse!", .func = ft_vec._reverse_in_place },

    .{ .name = "<string>", .func = ft_string._make },
    .{ .name = "<string>,clone", .func = ft_string._clone },
    .{ .name = "string-append!", .func = ft_string._append_in_place },
    .{ .name = "string>symbol", .func = ft_string._to_symbol },
    .{ .name = "string>vec", .func = ft_string._to_vec },
    .{ .name = "strget", .func = ft_string._get },
    .{ .name = "strlen", .func = ft_string._len },

    .{ .name = "<map>", .func = ft_map._make },
    .{ .name = "mset!", .func = ft_map._set },
    .{ .name = "mget", .func = ft_map._get },

    .{ .name = "<file>,open", .func = ft_file._open },
    .{ .name = "<file>,std", .func = ft_file._std },
    .{ .name = "file.filepath", .func = ft_file._filepath },
    .{ .name = "file.read-char", .func = ft_file._read_char },
    .{ .name = "file.peek-char", .func = ft_file._peek_char },
    .{ .name = "file.read-delimiter", .func = ft_file._read_delimiter },
    .{ .name = "file.read-all", .func = ft_file._read_all },
    .{ .name = "file.display", .func = ft_file._display },
    .{ .name = "file.write", .func = ft_file._write },
    .{ .name = "file.write-char", .func = ft_file._write_char },
    .{ .name = "file.write-all", .func = ft_file._write_all },
};
