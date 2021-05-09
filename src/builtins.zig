const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const lib = @import("lib.zig");
usingnamespace lib;

//;

// typecheck after you get all the args u want

//;

// TODO need
// functions
//   functional stuff
//     compose
//     map function for vecs vs protos should be specialized
//       vmap! mmap!
//     map fold
//       should i treat the vec like a stack?
//       something more like 'each' makes more sense
//         would be cool if i could temporarily use the vec as a stack
//   printing functions
//     write
//       need to translate '\n' in strings to a "\n"
//   math stuff
//     handle integer overflow
//   more string manipulation
//     things that take chars
// types
//   make sure accessing them from within zig is easy

// TODO want
// functions
//   bitwise operators
//     want like u64 type or something
// results
// contiguous vector thing
//   []i64, []f64 etc
// math
//   fract
// vec
//   { 1 2 3 4 } <vec>,clone
//     essentially just <quotation>,clone quotation>vec
//       could probably just write it in orth but gotta make sure the memory stuff works

// Vec
//   vecs might be able to use the optimization
//   that if you are mapping over them
//     if you know that the original vec doesnt have any refs to it anymore
//   u can reuse it for the new vector

//;

pub fn f_panic(t: *Thread) Thread.Error!void {
    return error.Panic;
}

pub fn f_define(t: *Thread) Thread.Error!void {
    const name = try t.stack.pop();
    const value = try t.stack.pop();
    if (name != .Symbol) return error.TypeError;

    if (t.vm.word_table.items[name.Symbol]) |prev| {
        // TODO handle overwrite
        //  need to handle deleteing the value youre replacing
    } else {
        t.vm.word_table.items[name.Symbol] = value;
    }
}

pub fn f_set_doc(t: *Thread) Thread.Error!void {
    const val = try t.stack.pop();
    const doc_string = try t.stack.pop();
    if (val != .Word and val != .Symbol) return error.TypeError;
    // TODO have it so it doesnt have to be a literal string
    if (doc_string != .String) return error.TypeError;

    const id = switch (val) {
        .Word => |word| word,
        .Symbol => |sym| sym,
        else => unreachable,
    };

    if (t.vm.docs_table.items[id]) |prev| {
        // TODO handle overwrite
    } else {
        t.vm.docs_table.items[id] = try t.vm.allocator.dupe(u8, doc_string.String);
    }
}
pub fn f_get_doc(t: *Thread) Thread.Error!void {
    const val = try t.stack.pop();
    if (val != .Word and val != .Symbol) return error.TypeError;

    const id = switch (val) {
        .Word => |word| word,
        .Symbol => |sym| sym,
        else => unreachable,
    };

    // TODO docs not found error
    try t.stack.push(.{ .String = t.vm.docs_table.items[id].? });
}

pub fn f_ref(t: *Thread) Thread.Error!void {
    const name = try t.stack.pop();
    if (name != .Symbol) return error.TypeError;

    if (t.vm.word_table.items[name.Symbol]) |val| {
        try t.stack.push(t.vm.dupValue(val));
    } else {
        t.vm.error_info.word_not_found = t.vm.symbol_table.items[name.Symbol];
        return error.WordNotFound;
    }
}

pub fn f_eval(t: *Thread) Thread.Error!void {
    const val = try t.stack.pop();
    try t.evaluateValue(val, 0);
    t.vm.dropValue(val);
}

pub fn f_clear_stack(t: *Thread) Thread.Error!void {
    // TODO handle rc
    t.stack.data.items.len = 0;
}

pub fn f_print_top(t: *Thread) Thread.Error!void {
    std.debug.print("TOP| ", .{});
    t.nicePrintValue(try t.stack.peek());
    std.debug.print("\n", .{});
}

pub fn f_print_stack(t: *Thread) Thread.Error!void {
    std.debug.print("STACK| len: {}\n", .{t.stack.data.items.len});
    for (t.stack.data.items) |it, i| {
        std.debug.print("  {}| ", .{t.stack.data.items.len - i - 1});
        t.nicePrintValue(it);
        std.debug.print("\n", .{});
    }
}

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
        .FFI_Fn => |val| std.debug.print("fn({})", .{t.vm.symbol_table.items[val.name]}),
        .FFI_Ptr => |ptr| t.vm.type_table.items[ptr.type_id].display_fn(t, ptr),
    }
}

pub fn f_display(t: *Thread) Thread.Error!void {
    displayValue(t, try t.stack.pop());
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

pub fn f_parse(t: *Thread) Thread.Error!void {
    const str = try t.stack.pop();
    if (str != .String) return error.TypeError;

    var tokens = Tokenizer.init(str.String);

    while (tokens.next() catch unreachable) |tok| {
        // TODO i dont think this is right but idk
        try t.evaluateValue(t.vm.parse(tok) catch unreachable, 0);
    }
}

// built in types ===

pub fn f_type_of(t: *Thread) Thread.Error!void {
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

pub fn f_string_to_symbol(t: *Thread) Thread.Error!void {
    const str = try t.stack.pop();
    if (str != .String) return error.TypeError;
    try t.stack.push(.{ .Symbol = try t.vm.internSymbol(str.String) });
}

pub fn f_symbol_to_string(t: *Thread) Thread.Error!void {
    const sym = try t.stack.pop();
    if (sym != .Symbol) return error.TypeError;
    try t.stack.push(.{ .String = t.vm.symbol_table.items[sym.Symbol] });
}

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
        .FFI_Ptr => |ptr| t.vm.type_table.items[ptr.type_id].equivalent_fn(t, ptr, b),
    } else blk: {
        // TODO
        break :blk false;
    };
}

pub fn f_equivalent(t: *Thread) Thread.Error!void {
    const a = try t.stack.pop();
    const b = try t.stack.pop();
    const are_equivalent = areValuesEquivalent(t, a, b);
    t.vm.dropValue(a);
    t.vm.dropValue(b);
    try t.stack.push(.{ .Boolean = are_equivalent });
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
        .has_callable = false,
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

pub fn f_2dup(t: *Thread) Thread.Error!void {
    const a = try t.stack.peek();
    const b = (try t.stack.index(1)).*;
    try t.stack.push(t.vm.dupValue(b));
    try t.stack.push(t.vm.dupValue(a));
}

pub fn f_3dup(t: *Thread) Thread.Error!void {
    const a = try t.stack.peek();
    const b = (try t.stack.index(1)).*;
    const c = (try t.stack.index(2)).*;
    try t.stack.push(t.vm.dupValue(c));
    try t.stack.push(t.vm.dupValue(b));
    try t.stack.push(t.vm.dupValue(a));
}

pub fn f_over(t: *Thread) Thread.Error!void {
    const val = (try t.stack.index(1)).*;
    try t.stack.push(t.vm.dupValue(val));
}

pub fn f_2over(t: *Thread) Thread.Error!void {
    const v1 = (try t.stack.index(1)).*;
    const v2 = (try t.stack.index(2)).*;
    try t.stack.push(t.vm.dupValue(v2));
    try t.stack.push(t.vm.dupValue(v1));
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

pub fn f_rot(t: *Thread) Thread.Error!void {
    const z = try t.stack.pop();
    const y = try t.stack.pop();
    const x = try t.stack.pop();
    try t.stack.push(y);
    try t.stack.push(z);
    try t.stack.push(x);
}

pub fn f_neg_rot(t: *Thread) Thread.Error!void {
    const z = try t.stack.pop();
    const y = try t.stack.pop();
    const x = try t.stack.pop();
    try t.stack.push(z);
    try t.stack.push(x);
    try t.stack.push(y);
}

// combinators ===

// TODO quot doesnt have to be a quotation
pub fn f_dip(t: *Thread) Thread.Error!void {
    const quot = try t.stack.pop();
    const restore = try t.stack.pop();
    if (quot != .Quotation) return error.TypeError;
    try t.restore_stack.push(restore);
    try t.evaluateValue(quot, 1);
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

        // TODO probably rename this to inc
        pub fn ref(self: *Self) *Self {
            self.ref_ct += 1;
            return self;
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

pub const ft_string = struct {
    const Self = @This();

    pub var ffi_type = FFI_Type{
        .name = "ffi-string",
        .display_fn = display,
        .dup_fn = dup,
        .drop_fn = drop,
    };

    pub fn display(t: *Thread, ptr: FFI_Ptr) void {
        const rc = ptr.cast(Rc(ArrayList(u8)));
        std.debug.print("\"{}\"", .{rc.obj.items});
    }

    pub fn dup(vm: *VM, ptr: FFI_Ptr) FFI_Ptr {
        var rc = ptr.cast(Rc(ArrayList(u8)));
        return Self.ffi_type.makePtr(rc.ref());
    }

    pub fn drop(vm: *VM, ptr: FFI_Ptr) void {
        var rc = ptr.cast(Rc(ArrayList(u8)));
        if (!rc.dec()) {
            rc.obj.deinit();
            vm.allocator.destroy(rc);
        }
    }

    //;

    fn makeRcFromSlice(allocator: *Allocator, slice: []const u8) Allocator.Error!*Rc(ArrayList(u8)) {
        var rc = try allocator.create(Rc(ArrayList(u8)));
        errdefer allocator.destroy(rc);
        rc.* = Rc(ArrayList(u8)).init();
        rc.obj = ArrayList(u8).init(allocator);
        try rc.obj.appendSlice(slice);

        return rc;
    }

    pub fn _make(t: *Thread) Thread.Error!void {
        var rc = try t.vm.allocator.create(Rc(ArrayList(u8)));
        errdefer t.vm.allocator.destroy(rc);
        rc.* = Rc(ArrayList(u8)).init();
        rc.obj = ArrayList(u8).init(t.vm.allocator);

        try t.stack.push(.{ .FFI_Ptr = Self.ffi_type.makePtr(rc.ref()) });
    }

    pub fn _clone(t: *Thread) Thread.Error!void {
        const other = try t.stack.pop();
        switch (other) {
            .String => |str| {
                var rc = try makeRcFromSlice(t.vm.allocator, str);
                try t.stack.push(.{ .FFI_Ptr = Self.ffi_type.makePtr(rc.ref()) });
            },
            .FFI_Ptr => |ptr| {
                try Self.ffi_type.checkType(ptr);

                var other_rc = ptr.cast(Rc(ArrayList(u8)));
                var rc = try makeRcFromSlice(t.vm.allocator, other_rc.obj.items);

                try t.stack.push(.{ .FFI_Ptr = Self.ffi_type.makePtr(rc.ref()) });

                t.vm.dropValue(other);
            },
            else => return error.TypeError,
        }
    }

    pub fn _append_in_place(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const other = try t.stack.pop();
        if (other != .String and other != .FFI_Ptr) return error.TypeError;
        if (other == .FFI_Ptr) {
            try Self.ffi_type.checkType(other.FFI_Ptr);
        }

        const rc = switch (this) {
            .String => |str| try makeRcFromSlice(t.vm.allocator, str),
            .FFI_Ptr => |ptr| blk: {
                try Self.ffi_type.checkType(ptr);
                break :blk ptr.cast(Rc(ArrayList(u8)));
            },
            else => return error.TypeError,
        };

        switch (other) {
            .String => |o_str| try rc.obj.appendSlice(o_str),
            .FFI_Ptr => |o_ptr| {
                const o_str = o_ptr.cast(Rc(ArrayList(u8))).obj.items;
                try rc.obj.appendSlice(o_str);
            },
            else => unreachable,
        }

        try t.stack.push(.{ .FFI_Ptr = Self.ffi_type.makePtr(rc.ref()) });

        t.vm.dropValue(this);
        t.vm.dropValue(other);
    }

    pub fn _to_symbol(t: *Thread) Thread.Error!void {
        const this = try t.stack.pop();
        const str = switch (this) {
            .String => |str| str,
            .FFI_Ptr => |ptr| blk: {
                try Self.ffi_type.checkType(ptr);
                break :blk ptr.cast(Rc(ArrayList(u8))).obj.items;
            },
            else => return error.TypeError,
        };
        try t.stack.push(.{ .Symbol = try t.vm.internSymbol(str) });
        t.vm.dropValue(this);
    }
};

// quotation ===

// TODO
pub const ft_quotation = struct {
    const Self = @This();

    pub var ffi_type = FFI_Type{
        .name = "ffi-quotation",
        .call_fn = call,
        .display_fn = display,
        .dup_fn = dup,
        .drop_fn = drop,
    };

    pub fn call(t: *Thread, ptr: FFI_Ptr) []const Value {
        const rc = ptr.cast(Rc(ArrayList(Value)));
        return rc.obj.items;
    }

    pub fn display(t: *Thread, ptr: FFI_Ptr) void {
        const rc = ptr.cast(Rc(ArrayList(Value)));
        std.debug.print("q{{ ", .{});
        for (rc.obj.items) |v| {
            t.nicePrintValue(v);
            std.debug.print(" ", .{});
        }
        std.debug.print("}}", .{});
    }

    pub fn dup(vm: *VM, ptr: FFI_Ptr) FFI_Ptr {
        var rc = ptr.cast(Rc(ArrayList(Value)));
        return Self.ffi_type.makePtr(rc.ref());
    }

    pub fn drop(vm: *VM, ptr: FFI_Ptr) void {
        var rc = ptr.cast(Rc(ArrayList(Value)));
        if (!rc.dec()) {
            for (rc.obj.items) |val| {
                vm.dropValue(val);
            }
            rc.obj.deinit();
            vm.allocator.destroy(rc);
        }
    }

    //;

    fn makeRcFromSlice(allocator: *Allocator, slice: []const Value) Allocator.Error!*Rc(ArrayList(Value)) {
        var rc = try allocator.create(Rc(ArrayList(Value)));
        errdefer allocator.destroy(rc);
        rc.* = Rc(ArrayList(Value)).init();
        rc.obj = ArrayList(Value).init(allocator);
        try rc.obj.appendSlice(slice);

        return rc;
    }

    pub fn _make(t: *Thread) Thread.Error!void {
        var rc = try t.vm.allocator.create(Rc(ArrayList(Value)));
        errdefer t.vm.allocator.destroy(rc);
        rc.* = Rc(ArrayList(Value)).init();
        rc.obj = ArrayList(Value).init(t.vm.allocator);

        try t.stack.push(.{ .FFI_Ptr = Self.ffi_type.makePtr(rc.ref()) });
    }

    pub fn _clone(t: *Thread) Thread.Error!void {
        const other = try t.stack.pop();
        switch (other) {
            .Quotation => |q| {
                var rc = try makeRcFromSlice(t.vm.allocator, q);
                try t.stack.push(.{ .FFI_Ptr = Self.ffi_type.makePtr(rc.ref()) });
            },
            .FFI_Ptr => |ptr| {
                try Self.ffi_type.checkType(ptr);

                var other_rc = ptr.cast(Rc(ArrayList(Value)));
                var rc = try makeRcFromSlice(t.vm.allocator, other_rc.obj.items);

                try t.stack.push(.{ .FFI_Ptr = Self.ffi_type.makePtr(rc.ref()) });

                t.vm.dropValue(other);
            },
            else => return error.TypeError,
        }
    }

    pub fn _push(t: *Thread) Thread.Error!void {
        // TODO copy on write
        const ptr = try t.stack.pop();
        const val = try t.stack.pop();
        if (ptr != .FFI_Ptr) return error.TypeError;
        try Self.ffi_type.checkType(ptr.FFI_Ptr);

        var rc = ptr.FFI_Ptr.cast(Rc(ArrayList(Value)));
        try rc.obj.append(val);

        t.vm.dropValue(ptr);
    }

    pub fn _insert(t: *Thread) Thread.Error!void {
        // TODO copy on write
        const ptr = try t.stack.pop();
        const at = try t.stack.pop();
        const val = try t.stack.pop();
        if (ptr != .FFI_Ptr) return error.TypeError;
        try Self.ffi_type.checkType(ptr.FFI_Ptr);
        if (at != .Int) return error.TypeError;

        var rc = ptr.FFI_Ptr.cast(Rc(ArrayList(Value)));
        try rc.obj.insert(@intCast(usize, at.Int), val);

        t.vm.dropValue(ptr);
    }

    // TODO append

    pub fn _set(t: *Thread) Thread.Error!void {
        // TODO copy on write
        const ptr = try t.stack.pop();
        const idx = try t.stack.pop();
        const val = try t.stack.pop();
        if (ptr != .FFI_Ptr) return error.TypeError;
        try Self.ffi_type.checkType(ptr.FFI_Ptr);
        if (idx != .Int) return error.TypeError;

        var rc = ptr.FFI_Ptr.cast(Rc(ArrayList(Value)));
        rc.obj.items[@intCast(usize, idx.Int)] = t.vm.dupValue(val);

        t.vm.dropValue(ptr);
    }

    pub fn _get(t: *Thread) Thread.Error!void {
        // TODO get from literal
        const ptr = try t.stack.pop();
        const idx = try t.stack.pop();
        if (ptr != .FFI_Ptr) return error.TypeError;
        try Self.ffi_type.checkType(ptr.FFI_Ptr);
        if (idx != .Int) return error.TypeError;

        var rc = ptr.FFI_Ptr.cast(Rc(ArrayList(Value)));
        try t.stack.push(t.vm.dupValue(rc.obj.items[@intCast(usize, idx.Int)]));

        t.vm.dropValue(ptr);
    }

    pub fn _reverse_in_place(t: *Thread) Thread.Error!void {
        const ptr = try t.stack.pop();
        if (ptr != .FFI_Ptr) return error.TypeError;
        try Self.ffi_type.checkType(ptr.FFI_Ptr);

        var rc = ptr.FFI_Ptr.cast(Rc(ArrayList(Value)));
        std.mem.reverse(Value, rc.obj.items);

        t.vm.dropValue(ptr);
    }
};

// vec ===

pub const ft_vec = struct {
    const Self = @This();

    pub var ffi_type = FFI_Type{
        .name = "vec",
        .display_fn = display,
        .dup_fn = dup,
        .drop_fn = drop,
    };

    pub fn display(t: *Thread, ptr: FFI_Ptr) void {
        const rc = ptr.cast(Rc(ArrayList(Value)));
        std.debug.print("v[ ", .{});
        for (rc.obj.items) |v| {
            t.nicePrintValue(v);
            std.debug.print(" ", .{});
        }
        std.debug.print("]", .{});
    }

    pub fn dup(vm: *VM, ptr: FFI_Ptr) FFI_Ptr {
        var rc = ptr.cast(Rc(ArrayList(Value)));
        return Self.ffi_type.makePtr(rc.ref());
    }

    pub fn drop(vm: *VM, ptr: FFI_Ptr) void {
        var rc = ptr.cast(Rc(ArrayList(Value)));
        if (!rc.dec()) {
            for (rc.obj.items) |val| {
                vm.dropValue(val);
            }
            rc.obj.deinit();
            vm.allocator.destroy(rc);
        }
    }

    //;

    // TODO all of these things need to be refactored if i wana reuse them for quotations
    pub fn _make(t: *Thread) Thread.Error!void {
        var rc = try t.vm.allocator.create(Rc(ArrayList(Value)));
        errdefer t.vm.allocator.destroy(rc);
        rc.* = Rc(ArrayList(Value)).init();
        rc.obj = ArrayList(Value).init(t.vm.allocator);

        try t.stack.push(.{ .FFI_Ptr = Self.ffi_type.makePtr(rc.ref()) });
    }

    pub fn _push(t: *Thread) Thread.Error!void {
        const ptr = try t.stack.pop();
        const val = try t.stack.pop();
        if (ptr != .FFI_Ptr) return error.TypeError;
        try Self.ffi_type.checkType(ptr.FFI_Ptr);

        var rc = ptr.FFI_Ptr.cast(Rc(ArrayList(Value)));
        try rc.obj.append(val);

        t.vm.dropValue(ptr);
    }

    pub fn _set(t: *Thread) Thread.Error!void {
        const ptr = try t.stack.pop();
        const idx = try t.stack.pop();
        const val = try t.stack.pop();
        if (ptr != .FFI_Ptr) return error.TypeError;
        try Self.ffi_type.checkType(ptr.FFI_Ptr);
        if (idx != .Int) return error.TypeError;

        var rc = ptr.FFI_Ptr.cast(Rc(ArrayList(Value)));
        rc.obj.items[@intCast(usize, idx.Int)] = t.vm.dupValue(val);

        t.vm.dropValue(ptr);
    }

    pub fn _get(t: *Thread) Thread.Error!void {
        const ptr = try t.stack.pop();
        const idx = try t.stack.pop();
        if (ptr != .FFI_Ptr) return error.TypeError;
        try Self.ffi_type.checkType(ptr.FFI_Ptr);
        if (idx != .Int) return error.TypeError;

        var rc = ptr.FFI_Ptr.cast(Rc(ArrayList(Value)));
        try t.stack.push(t.vm.dupValue(rc.obj.items[@intCast(usize, idx.Int)]));

        t.vm.dropValue(ptr);
    }

    pub fn _len(t: *Thread) Thread.Error!void {
        const ptr = try t.stack.pop();
        if (ptr != .FFI_Ptr) return error.TypeError;
        try Self.ffi_type.checkType(ptr.FFI_Ptr);

        var rc = ptr.FFI_Ptr.cast(Rc(ArrayList(Value)));
        try t.stack.push(.{ .Int = @intCast(i32, rc.obj.items.len) });

        t.vm.dropValue(ptr);
    }

    pub fn _map_in_place(t: *Thread) Thread.Error!void {
        //         const ptr = try vm.stack.pop();
        //         if (ptr != .FFI_Ptr) return error.TypeError;
        //         try Self.ffi_type.checkType(ptr.FFI_Ptr);
        //
        //         var rc = ptr.FFI_Ptr.cast(Rc(ArrayList(Value)));
        //         std.mem.reverse(Value, rc.obj.items);
        //
        //         vm.dropValue(ptr);
    }

    pub fn _reverse_in_place(t: *Thread) Thread.Error!void {
        const ptr = try t.stack.pop();
        if (ptr != .FFI_Ptr) return error.TypeError;
        try Self.ffi_type.checkType(ptr.FFI_Ptr);

        var rc = ptr.FFI_Ptr.cast(Rc(ArrayList(Value)));
        std.mem.reverse(Value, rc.obj.items);

        t.vm.dropValue(ptr);
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

    //     const Map = std.AutoHashMap(usize, Value);
    //
    //     pub const ft = FFI_TypeDefinition(Map, display, null, finalize);
    //
    //     pub fn display(vm: *VM, rc: *FFI_Rc) void {
    //         const map = rc.cast(Map);
    //         std.debug.print("m[ ", .{});
    //         var iter = map.iterator();
    //         while (iter.next()) |entry| {
    //             std.debug.print("{}: ", .{vm.symbol_table.items[entry.key]});
    //             vm.nicePrintValue(entry.value);
    //             std.debug.print(" ", .{});
    //         }
    //         std.debug.print("]", .{});
    //     }
    //
    //     pub fn finalize(vm: *VM, rc: *FFI_Rc) void {
    //         var map = rc.cast(Map);
    //         var iter = map.iterator();
    //         while (iter.next()) |entry| {
    //             var val = entry.value;
    //             if (val == .Ref) {
    //                 _ = val.Ref.rc.dec(vm);
    //             }
    //         }
    //         map.deinit();
    //         vm.allocator.destroy(map);
    //     }
    //
    //     //;
    //
    //     pub fn _make(vm: *VM) Thread.Error!void {
    //         var map = try vm.allocator.create(Map);
    //         errdefer vm.allocator.destroy(map);
    //         map.* = Map.init(vm.allocator);
    //
    //         var rc = try vm.allocator.create(FFI_Rc);
    //         rc.* = Self.ft.makeRc(map);
    //         errdefer vm.allocator.destroy(rc);
    //
    //         try vm.stack.push(.{ .Ref = rc.ref() });
    //     }
    //
    //     pub fn _set(vm: *VM) Thread.Error!void {
    //         const ref = try vm.stack.pop();
    //         const sym = try vm.stack.pop();
    //         const value = try vm.stack.pop();
    //         try Self.ft.checkType(ref);
    //         if (sym != .Symbol) return error.TypeError;
    //
    //         if (!ref.Ref.rc.dec(vm)) return;
    //
    //         var map = ref.Ref.rc.cast(Map);
    //
    //         // TODO handle overwrite
    //         try map.put(sym.Symbol, value);
    //     }
    //
    //     pub fn _get(vm: *VM) Thread.Error!void {
    //         const ref = try vm.stack.pop();
    //         const sym = try vm.stack.pop();
    //         try Self.ft.checkType(ref);
    //         if (sym != .Symbol) return error.TypeError;
    //
    //         if (!ref.Ref.rc.dec(vm)) return;
    //
    //         var map = ref.Ref.rc.cast(Map);
    //
    //         if (map.get(sym.Symbol)) |val| {
    //             try vm.stack.push(val.clone());
    //             try vm.stack.push(.{ .Boolean = true });
    //         } else {
    //             try vm.stack.push(.{ .Boolean = false });
    //             try vm.stack.push(.{ .Boolean = false });
    //         }
    //     }
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
        .name = "doc!",
        .func = f_set_doc,
    },
    .{
        .name = "doc",
        .func = f_get_doc,
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
        .name = "display",
        .func = f_display,
    },

    .{
        .name = "read",
        .func = f_read,
    },
    .{
        .name = "parse",
        .func = f_parse,
    },

    .{
        .name = "type-of",
        .func = f_type_of,
    },
    .{
        .name = "ffi-type-of",
        .func = f_ffi_type_of,
    },
    .{
        .name = "word>symbol",
        .func = f_word_to_symbol,
    },
    .{
        .name = "symbol>word",
        .func = f_symbol_to_word,
    },
    .{
        .name = "string>symbol",
        .func = f_string_to_symbol,
    },
    .{
        .name = "symbol>string",
        .func = f_symbol_to_string,
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
        .name = "eqv?",
        .func = f_equivalent,
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
        .name = "<string>",
        .func = ft_string._make,
    },
    .{
        .name = "<string>,clone",
        .func = ft_string._clone,
    },
    .{
        .name = "string-append",
        .func = ft_string._append_in_place,
    },
    .{
        .name = "string>symbol",
        .func = ft_string._to_symbol,
    },

    .{
        .name = "<quotation>",
        .func = ft_quotation._make,
    },
    .{
        .name = "<quotation>,clone",
        .func = ft_quotation._clone,
    },
    .{
        .name = "qpush!",
        .func = ft_quotation._push,
    },
    .{
        .name = "qinsert!",
        .func = ft_quotation._insert,
    },
    .{
        .name = "qget",
        .func = ft_quotation._get,
    },
    .{
        .name = "qset!",
        .func = ft_quotation._set,
    },
    .{
        .name = "qreverse!",
        .func = ft_quotation._reverse_in_place,
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
        .name = "vset!",
        .func = ft_vec._set,
    },
    .{
        .name = "vlen",
        .func = ft_vec._len,
    },
    .{
        .name = "vmap!",
        .func = ft_vec._map_in_place,
    },
    .{
        .name = "vreverse!",
        .func = ft_vec._reverse_in_place,
    },
    //     .{
    //         .name = "<map>",
    //         .func = ft_proto._make,
    //     },
    //     .{
    //         .name = "mget*",
    //         .func = ft_proto._get,
    //     },
    //     .{
    //         .name = "mset!",
    //         .func = ft_proto._set,
    //     },
};
