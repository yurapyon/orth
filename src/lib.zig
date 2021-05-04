const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ascii = std.ascii;

//;

// stack 0 is top

// TODO need
// tokenizer
//   char type? could just use ints
//     maybe do them like #\A #\b etc
//     # is an escaper thing
//   multiline strings
//     do the thing where leading spaces are removed
//     "hello
//      world" should just be "hello\nworld"
//   string escaping
//   multiline comments?
//     could use ( )
// memory management
//   currently literals returned from parser need to stay around while vm is evaluating
//     would be nice if this wasnt the case ?
//     this goes along with copying strings and symbols and keeping them in the vm
//   rc
//     locals have to account for rc
//     now that i have Rcs is there a way that i could pass unmanaged ptrs
//       and have the same functions work on those
//     reference counting for strings quotations
//         being on the stack or in word_table counts as a reference
//         could do manual memory management but i imagine that would get hard
//       string and quotation could be a *Cow(_) but, that complicates memory management
//         would be better if they were Rc(Cow(_))

// TODO want
// error reporting
//   stack trace thing
//   tokenize with column number/word number
//     use line_num in parser code
// handle recursion better
//   right now it seems theres a limit b/c zig stack depth
// currying changes how quoations work
//   { values, quotation }
//   can also be used for composoition
//   could do it by letting foreign types mark themselves as callable
// namespaces / envs would be nice but have to think abt how they should work
// return stack
//   rename to alt_stack or something
// maybe make 'and' and 'or' work like lua
//   are values besides #t and #f able to work in places where booleans are accepted
//   usually this is because everything is nullable, but i dont really want that in orth

// TODO QOL
// better int parser
//   hex ints
// better float parser
// certain things cant be symbols
//   because symbols are what you use to name functions and stuff
// vm should have log/print functions or something
//     so u can control where vm messages get printed
//     integrate this into nicePrint functions
//   if nice print is supposed to return strings then idk
//   nicePrint fns take a Writer
// records
//   need to be significantly different than foreign ptrs
//   foreign ptrs are pretty easy to use so idk
// locals
//   locals memory management
//   different way of knowing where to restore locals to
//     so ForeignFns can do stuff with locals
//   should you look back out of your current 'scope'?
//     no probably not
// quotations
//   test that modifying a quotation works
//   { and } are words
//   could be foreign types if { can turn off evaluation of literals
//     } handles backtracking like ]vec does and turns it back on
//   need a way to put literals on the stack
//     certain types of values cant be turned back into literals and certain things can
//   escaping words like  \ word  makes more sense
//     if \ just turns off evaluation for 1 word
//   ( turns off tokenizing until )
//   ; turns off tokenizing until newline

// errors ===

pub const ErrorInfo = struct {
    line_number: usize,
    word_not_found: []const u8,
};

pub const StackError = error{
    StackOverflow,
    StackUnderflow,
    OutOfBounds,
} || Allocator.Error;

pub const TokenizeError = error{
    InvalidString,
    InvalidWord,
} || Allocator.Error;

pub const ParseError = error{InvalidSymbol} || Allocator.Error;

pub const EvalError = error{
    WordNotFound,
    QuotationUnderflow,
    TypeError,
    DivideByZero,
    NegativeDenominator,
    Panic,
    InternalError,
} || StackError || Allocator.Error;

//;

pub fn Cow(comptime T: type) type {
    return struct {
        const Self = @This();

        const_data: []const T,
        data: ArrayList(T),
        owns_data: bool,

        pub fn init(allocator: *Allocator, data: []const T) Self {
            return .{
                .const_data = data,
                .data = ArrayList(T).init(allocator),
                .owns_data = false,
            };
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit();
        }

        pub fn get(self: Self) []const T {
            if (self.owns_data) {
                return self.data.items;
            } else {
                return self.const_data;
            }
        }

        pub fn getMut(self: *Self) Allocator.Error![]T {
            if (!self.owns_data) {
                try self.data.appendSlice(self.const_data);
                self.owns_data = true;
            }
            return self.data.items;
        }
    };
}

pub fn Stack(comptime T: type) type {
    return struct {
        const Self = @This();

        data: ArrayList(T),

        pub fn init(allocator: *Allocator) Self {
            return .{
                .data = ArrayList(T).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit();
        }

        //;

        pub fn push(self: *Self, obj: T) Allocator.Error!void {
            try self.data.append(obj);
        }

        pub fn pop(self: *Self) StackError!T {
            if (self.data.items.len == 0) {
                return error.StackUnderflow;
            }
            const ret = self.data.items[self.data.items.len - 1];
            self.data.items.len -= 1;
            return ret;
        }

        pub fn peek(self: *Self) StackError!T {
            return self.index(0);
        }

        // TODO
        // original idea for index was to reaturn a pointer
        //   so it could be used for stuff like swap and rot
        pub fn index(self: *Self, idx: usize) StackError!T {
            if (idx >= self.data.items.len) {
                return error.OutOfBounds;
            }
            return self.data.items[self.data.items.len - idx - 1];
        }

        pub fn clear(self: *Self) void {
            self.data.items.len = 0;
        }
    };
}

//;

pub const Token = struct {
    pub const Type = enum {
        String,
        Word,
    };

    ty: Type,
    str: []const u8,
    line_num: usize,
};

pub const Literal = union(enum) {
    Int: i32,
    Float: f32,
    Boolean: bool,
    String: []const u8,
    Word: usize,
    Symbol: usize,
    QuoteOpen,
    QuoteClose,
};

//;

pub const FFI_Fn = struct {
    pub const Function = fn (vm: *VM) EvalError!void;

    name: usize,
    func: Function,
};

pub fn FFI_TypeDefinition(
    comptime T: type,
    comptime display_fn_: ?fn (*VM, *FFI_Rc) void,
    comptime equals_fn_: ?fn (*VM, *FFI_Rc, *FFI_Rc) bool,
    comptime finalizer_fn_: ?fn (*VM, *FFI_Rc) void,
) type {
    return struct {
        const display_fn = display_fn_ orelse defaultDisplay;
        const equals_fn = equals_fn_ orelse defaultEquals;
        const finalizer_fn = finalizer_fn_ orelse defaultFinalizer;

        var type_id: usize = undefined;

        fn defaultDisplay(vm: *VM, rc: *const FFI_Rc) void {
            std.debug.print("*<{} {} {}>", .{
                rc.type_id,
                rc.data,
                rc.ref_ct,
            });
        }

        fn defaultEquals(vm: *VM, rc1: *const FFI_Rc, rc2: *const FFI_Rc) bool {
            return rc1 == rc2;
        }

        fn defaultFinalizer(vm: *VM, rc: *FFI_Rc) void {}

        //;

        fn getAsFFI_Type() FFI_Type {
            return .{
                .display_fn = display_fn,
                .equals_fn = equals_fn,
                .finalizer_fn = finalizer_fn,
            };
        }

        pub fn makeRc(obj: *T) FFI_Rc {
            return FFI_Rc.init(type_id, obj);
        }

        pub fn checkType(val: Value) EvalError!void {
            if (val != .Ref or val.Ref.rc.type_id != type_id) {
                return error.TypeError;
            }
        }

        //         pub fn getField(
        //             vm: *VM,
        //             comptime ty: []const u8,
        //             comptime field: []const u8,
        //         ) EvalError!void {
        //             const val = try vm.stack.pop();
        //             const ptr = try assertValueIsType(val);
        //             try vm.stack.push(@unionInit(Value, ty, @field(ptr, field)));
        //         }
        //
        //         pub fn setField(
        //             vm: *VM,
        //             comptime ty: []const u8,
        //             comptime field: []const u8,
        //             set_to: Value,
        //         ) EvalError!void {
        //             const val = try vm.stack.peek();
        //             const ptr = try assertValueIsType(val);
        //             @field(ptr, field) = @field(set_to, ty);
        //         }
    };
}

pub const FFI_Type = struct {
    // TODO maybe have these as optionals
    //   have the vm worry about wether to use default fn or not
    //   then you can turn speciallized display fns on or off
    display_fn: fn (*VM, *FFI_Rc) void,
    equals_fn: fn (*VM, *FFI_Rc, *FFI_Rc) bool,
    finalizer_fn: fn (*VM, *FFI_Rc) void,
};

pub const FFI_Rc = struct {
    const Self = @This();

    pub const Ref = struct {
        rc: *Self,
    };

    pub const Ptr = opaque {};

    type_id: usize,
    data: *Ptr,
    ref_ct: usize,

    fn init(type_id: usize, obj: anytype) Self {
        return .{
            .type_id = type_id,
            .data = @ptrCast(*Ptr, obj),
            .ref_ct = 0,
        };
    }

    pub fn cast(self: Self, comptime T: type) *T {
        return @ptrCast(*T, @alignCast(@alignOf(T), self.data));
    }

    pub fn ref(self: *Self) Ref {
        self.ref_ct += 1;
        return .{ .rc = self };
    }

    // returns if the obj is alive or not
    pub fn dec(self: *Self, vm: *VM) bool {
        std.debug.assert(self.ref_ct > 0);
        self.ref_ct -= 1;
        const should_free = self.ref_ct == 0;
        if (should_free) {
            vm.type_table.items[self.type_id].finalizer_fn(vm, self);
            vm.allocator.destroy(self);
        }

        return !should_free;
    }
};

// // TODO maybe just rename to Pointer
// pub const ForeignPtr = struct {
//     const Self = @This();
//     pub const Ptr = opaque {};
//
//     type_id: usize,
//     ptr: Rc(Ptr).Ref,
//
//     pub fn cast(self: Self, comptime T: type) *T {
//         return @ptrCast(*T, @alignCast(@alignOf(T), self.ptr));
//     }
// };
//
pub const Value = union(enum) {
    const Self = @This();

    Int: i32,
    Float: f32,
    Boolean: bool,
    Sentinel,
    String: usize,
    Symbol: usize,
    Quotation: usize,
    FFI_Fn: FFI_Fn,
    Ref: FFI_Rc.Ref,

    pub fn clone(self: Self) Self {
        if (self == .Ref) {
            return .{ .Ref = self.Ref.rc.ref() };
        } else {
            return self;
        }
    }
};

//;

pub const Local = struct {
    name: usize,
    value: Value,
};

pub const VM = struct {
    const Self = @This();

    allocator: *Allocator,
    error_info: ErrorInfo,
    symbol_table: ArrayList([]const u8),
    word_table: ArrayList(?Value),
    type_table: ArrayList(FFI_Type),
    string_table: ArrayList(Cow(u8)),
    quotation_table: ArrayList(Cow(Literal)),
    stack: Stack(Value),
    return_stack: Stack(Value),
    locals: Stack(Local),

    pub fn init(allocator: *Allocator) Self {
        var ret = .{
            .allocator = allocator,
            .error_info = undefined,
            .symbol_table = ArrayList([]const u8).init(allocator),
            .word_table = ArrayList(?Value).init(allocator),
            .type_table = ArrayList(FFI_Type).init(allocator),
            .string_table = ArrayList(Cow(u8)).init(allocator),
            .quotation_table = ArrayList(Cow(Literal)).init(allocator),
            .stack = Stack(Value).init(allocator),
            .return_stack = Stack(Value).init(allocator),
            .locals = Stack(Local).init(allocator),
        };
        return ret;
    }

    pub fn deinit(self: *Self) void {
        for (self.word_table.items) |*val| {
            if (val.*) |*v| {
                if (v.* == .Ref) {
                    self.type_table.items[v.Ref.rc.type_id].finalizer_fn(self, v.Ref.rc);
                    self.allocator.destroy(v.Ref.rc);
                }
            }
        }

        self.locals.deinit();
        self.return_stack.deinit();
        self.stack.deinit();
        for (self.quotation_table.items) |*cow| {
            cow.deinit();
        }
        self.quotation_table.deinit();
        for (self.string_table.items) |*cow| {
            cow.deinit();
        }
        self.string_table.deinit();
        self.type_table.deinit();
        self.word_table.deinit();
        self.symbol_table.deinit();
    }

    // TODO
    // fix memory management so this makes more sense
    pub fn initBase(self: *Self) EvalError!void {
        try vm.defineWord("#t", .{ .Boolean = true });
        try vm.defineWord("#f", .{ .Boolean = false });
        try vm.defineWord("#sentinel", .{ .Sentinel = {} });

        for (builtins.builtins) |bi| {
            const idx = try vm.internSymbol(bi.name);
            vm.word_table.items[idx] = lib.Value{
                .FFI_Fn = .{
                    .name = idx,
                    .func = bi.func,
                },
            };
        }

        _ = try vm.defineForeignType(builtins.Vec.ft);
        _ = try vm.defineForeignType(builtins.Proto.ft);

        var base_f = try readFile(allocator, "src/base.orth");
        defer allocator.free(base_f);

        const base_toks = try vm.tokenize(base_f);
        defer base_toks.deinit();

        const base_lits = try vm.parse(base_toks.items);
        defer base_lits.deinit();

        try vm.eval(base_lits.items);
    }

    // tokenize ===

    fn charIsDelimiter(ch: u8) bool {
        return ascii.isSpace(ch) or ch == ';';
    }

    fn charIsWordValid(ch: u8) bool {
        return ch != '"';
    }

    pub fn tokenize(self: *Self, input: []const u8) TokenizeError!ArrayList(Token) {
        const State = enum {
            Empty,
            InComment,
            InString,
            InWord,
        };

        var state: State = .Empty;
        var start: usize = 0;
        var end: usize = 0;

        var ret = ArrayList(Token).init(self.allocator);
        errdefer ret.deinit();

        var line_num: usize = 1;

        for (input) |ch, i| {
            // TODO where to put this so line numbers are properly reported
            //   if \n causes the error
            if (ch == '\n') {
                line_num += 1;
            }

            switch (state) {
                .Empty => {
                    if (ascii.isSpace(ch)) {
                        continue;
                    }
                    state = switch (ch) {
                        ';' => .InComment,
                        '"' => .InString,
                        else => .InWord,
                    };
                    start = i;
                    end = start;
                },
                .InComment => {
                    if (ch == '\n') {
                        state = .Empty;
                    }
                },
                .InString => {
                    if (ch == '"') {
                        try ret.append(.{
                            .ty = .String,
                            .str = input[(start + 1)..(end + 1)],
                            .line_num = line_num,
                        });
                        state = .Empty;
                        continue;
                    } else if (ch == '\n') {
                        self.error_info.line_number = line_num;
                        return error.InvalidString;
                    }
                    end += 1;
                },
                .InWord => {
                    if (charIsDelimiter(ch)) {
                        try ret.append(.{
                            .ty = .Word,
                            .str = input[start..(end + 1)],
                            .line_num = line_num,
                        });
                        state = .Empty;
                        continue;
                    } else if (!charIsWordValid(ch)) {
                        self.error_info.line_number = line_num;
                        return error.InvalidWord;
                    }

                    end += 1;
                },
            }
        }

        switch (state) {
            .InString => {
                self.error_info.line_number = line_num;
                return error.InvalidString;
            },
            .InWord => {
                try ret.append(.{
                    .ty = .Word,
                    .str = input[start..(end + 1)],
                    .line_num = line_num,
                });
            },
            else => {},
        }

        return ret;
    }

    // parse ===

    pub fn nicePrintLiteral(self: *Self, lit: Literal) void {
        switch (lit) {
            .Int => |val| std.debug.print("{}", .{val}),
            .Float => |val| std.debug.print("{d}f", .{val}),
            .Boolean => |val| {
                const str = if (val) "#t" else "#f";
                std.debug.print("{s}", .{str});
            },
            .String => |val| std.debug.print("\"{}\"", .{val}),
            .Word => |val| std.debug.print("{}", .{self.symbol_table.items[val]}),
            .Symbol => |val| std.debug.print(":{}", .{self.symbol_table.items[val]}),
            .QuoteOpen => std.debug.print("{{", .{}),
            .QuoteClose => std.debug.print("}}", .{}),
        }
    }

    pub fn internSymbol(self: *Self, str: []const u8) Allocator.Error!usize {
        for (self.symbol_table.items) |st_str, i| {
            if (std.mem.eql(u8, str, st_str)) {
                return i;
            }
        }

        // TODO need
        // copy strings on interning
        //   makes sense for if u can generate symbols at runtime
        const idx = self.symbol_table.items.len;
        try self.symbol_table.append(str);
        try self.word_table.append(null);
        return idx;
    }

    pub fn parse(self: *Self, tokens: []const Token) ParseError!ArrayList(Literal) {
        var ret = ArrayList(Literal).init(self.allocator);
        errdefer ret.deinit();

        for (tokens) |token| {
            switch (token.ty) {
                .String => try ret.append(.{ .String = token.str }),
                .Word => {
                    var try_parse_float =
                        !std.mem.eql(u8, token.str, "+") and
                        !std.mem.eql(u8, token.str, "-") and
                        !std.mem.eql(u8, token.str, ".");
                    const fl = std.fmt.parseFloat(f32, token.str) catch null;

                    if (token.str[0] == ':') {
                        if (token.str.len == 1) {
                            self.error_info.line_number = 0;
                            return error.InvalidSymbol;
                        } else {
                            try ret.append(.{ .Symbol = try self.internSymbol(token.str[1..]) });
                        }
                    } else if (std.fmt.parseInt(i32, token.str, 10) catch null) |i| {
                        try ret.append(.{ .Int = i });
                    } else if (try_parse_float and (fl != null)) {
                        try ret.append(.{ .Float = fl.? });
                    } else if (std.mem.eql(u8, token.str, "{")) {
                        try ret.append(.{ .QuoteOpen = {} });
                    } else if (std.mem.eql(u8, token.str, "}")) {
                        try ret.append(.{ .QuoteClose = {} });
                    } else {
                        try ret.append(.{ .Word = try self.internSymbol(token.str) });
                    }
                },
            }
        }

        return ret;
    }

    // eval ===

    pub fn nicePrintValue(self: *Self, value: Value) void {
        switch (value) {
            .Int => |val| std.debug.print("{}", .{val}),
            .Float => |val| std.debug.print("{d}f", .{val}),
            .Boolean => |val| {
                const str = if (val) "#t" else "#f";
                std.debug.print("{s}", .{str});
            },
            .Sentinel => std.debug.print("#sentinel", .{}),
            .Symbol => |val| std.debug.print(":{}", .{self.symbol_table.items[val]}),
            .String => |val| std.debug.print("\"{}\"", .{self.string_table.items[val].get()}),
            .Quotation => |val| {
                std.debug.print("q{{ ", .{});
                for (self.quotation_table.items[val].get()) |lit| {
                    self.nicePrintLiteral(lit);
                    std.debug.print(" ", .{});
                }
                std.debug.print("}}", .{});
            },
            .FFI_Fn => |val| std.debug.print("fn({})", .{self.symbol_table.items[val.name]}),
            .Ref => |ref| self.type_table.items[ref.rc.type_id].display_fn(self, ref.rc),
        }
    }

    pub fn installFFI_Type(self: *Self, comptime T: type) Allocator.Error!void {
        const idx = self.type_table.items.len;
        T.type_id = idx;
        try self.type_table.append(T.getAsFFI_Type());
    }

    pub fn defineWord(self: *Self, name: []const u8, value: Value) Allocator.Error!void {
        const idx = try self.internSymbol(name);
        self.word_table.items[idx] = value;
    }

    pub fn evaluateValue(self: *Self, val: Value) EvalError!void {
        switch (val) {
            .Quotation => |id| try self.eval(self.quotation_table.items[id].get()),
            .FFI_Fn => |fp| try fp.func(self),
            else => try self.stack.push(val.clone()),
        }
    }

    // TODO wordLookup needs to be out here to account for locals

    pub fn eval(self: *Self, literals: []const Literal) EvalError!void {
        // TODO QOL
        // could do quoations differently
        //   { inc quotation_level
        //   } back tracks to find most recent {
        //     creates []Literal using that info
        //       rather than using q_start and q_ct
        //   need to use a while loop insteda of for loop i think
        var quotation_level: usize = 0;
        var q_start: [*]const Literal = undefined;
        var q_ct: usize = 0;
        const restore_locals_len = self.locals.data.items.len;

        for (literals) |*lit| {
            switch (lit.*) {
                .QuoteOpen => {
                    quotation_level += 1;
                    if (quotation_level == 1) {
                        q_start = @ptrCast([*]const Literal, lit);
                        q_ct = 0;
                        continue;
                    }
                },
                .QuoteClose => {
                    if (quotation_level == 0) {
                        return error.QuotationUnderflow;
                    }
                    quotation_level -= 1;
                    if (quotation_level == 0) {
                        const slice = if (q_ct == 0) &[_]Literal{} else q_start[1..(q_ct + 1)];
                        const id = self.quotation_table.items.len;
                        try self.quotation_table.append(Cow(Literal).init(
                            self.allocator,
                            slice,
                        ));
                        try self.stack.push(.{ .Quotation = id });
                        continue;
                    }
                },
                else => {},
            }

            if (quotation_level > 0) {
                q_ct += 1;
                continue;
            }

            switch (lit.*) {
                .Int => |i| try self.stack.push(.{ .Int = i }),
                .Float => |f| try self.stack.push(.{ .Float = f }),
                .Boolean => |b| try self.stack.push(.{ .Boolean = b }),
                .String => |str| {
                    const id = self.string_table.items.len;
                    try self.string_table.append(Cow(u8).init(self.allocator, str));
                    try self.stack.push(.{ .String = id });
                },
                .Word => |idx| {
                    const current_locals_len = self.locals.data.items.len;
                    if (current_locals_len > restore_locals_len) {
                        var found_local = false;
                        for (self.locals.data.items[restore_locals_len..current_locals_len]) |local| {
                            if (idx == local.name) {
                                try self.evaluateValue(local.value);
                                found_local = true;
                            }
                        }
                        if (found_local) continue;
                    }

                    const val = self.word_table.items[idx];
                    if (val) |v| {
                        try self.evaluateValue(v);
                    } else {
                        self.error_info.word_not_found = self.symbol_table.items[idx];
                        return error.WordNotFound;
                    }
                },
                .Symbol => |idx| try self.stack.push(.{ .Symbol = idx }),
                .QuoteOpen, .QuoteClose => return error.InternalError,
            }
        }

        self.locals.data.items.len = restore_locals_len;
    }
};
