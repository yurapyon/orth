const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ascii = std.ascii;
const AutoHashMap = std.AutoHashMap;
const StringHashMap = std.StringHashMap;

//;

// TODO certain things cant be symbols
//   because symbols are what you use to name functions and stuff

// TODO locals

// records
//   need to be significantly different than foreign ptrs
//   foreign ptrs are pretty easy to use so idk

// TODO
// char type? could just use ints
// hex ints
// maybe do them like #\A #\b etc
// # is an escaper thing

// better int parser
// better float parser

// TODO
// move error_info into the vm

// TODO
// vm should have log/print functions or something
//   so u can control where vm messages get printed
//   integrate this into nicePrint functions
// if nice print is supposed to return strings then idk

// TODO
//   values should not have to be 'cloned'
//     they should all be pointers if they have data somewhere
// could use reference counting for memory management
// being on the stack or in word_table counts as a reference
// could do manual memory management but i imagine that would get hard

// string and quotation could be a *Cow(_) but, that complicates memory management
//   would be better if they were Rc(Cow(_))

// errors ===

pub const error_info = struct {
    pub var line_number: usize = undefined;
    pub var word_not_found: []const u8 = undefined;
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

// TODO have a "fixed stack" that can overflow?
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
            return (try self.index(0)).*;
        }

        pub fn index(self: *Self, idx: usize) StackError!*T {
            if (idx >= self.data.items.len) {
                return error.OutOfBounds;
            }
            return &self.data.items[self.data.items.len - idx - 1];
        }

        pub fn clear(self: *Self) void {
            self.data.items.len = 0;
        }
    };
}

// TODO tokenize with line numbers, for error reporting from parser
pub const Token = struct {
    pub const Type = enum {
        String,
        Word,
    };

    ty: Type,
    str: []const u8
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

pub const ForeignFn = fn (vm: *VM) EvalError!void;

pub const ForeignFnPtr = struct {
    name: usize,
    func: ForeignFn,
};

// TODO maybe just rename to Pointer
pub const ForeignPtr = struct {
    const Self = @This();
    pub const Ptr = opaque {};

    ty: usize,
    ptr: *Ptr,

    pub fn cast(self: Self, comptime T: type) *T {
        return @ptrCast(*T, @alignCast(@alignOf(T), self.ptr));
    }
};

pub fn ForeignTypeDef(
    comptime T: type,
    comptime display_fn_: ?fn (*VM, ForeignPtr) void,
    comptime equals_fn_: ?fn (*VM, ForeignPtr, ForeignPtr) bool,
) type {
    return struct {
        const name = @typeName(T);
        const display_fn = display_fn_ orelse defaultDisplay;
        const equals_fn = equals_fn_ orelse defaultEquals;

        var type_id: usize = undefined;

        pub fn foreignType() ForeignType {
            return .{
                .name = name,
                .display_fn = display_fn,
                .equals_fn = equals_fn,
            };
        }

        pub fn assertValueIsType(val: Value) EvalError!*T {
            if (val != .ForeignPtr or
                val.ForeignPtr.ty != type_id)
            {
                return error.TypeError;
            } else {
                return val.ForeignPtr.cast(T);
            }
        }

        pub fn makePtr(obj: *T) Value {
            return .{
                .ForeignPtr = .{
                    .ty = type_id,
                    .ptr = @ptrCast(*ForeignPtr.Ptr, obj),
                },
            };
        }

        pub fn getField(
            vm: *VM,
            comptime ty: []const u8,
            comptime field: []const u8,
        ) EvalError!void {
            const val = try vm.stack.pop();
            const ptr = try assertValueIsType(val);
            try vm.stack.push(@unionInit(Value, ty, @field(ptr, field)));
        }

        pub fn setField(
            vm: *VM,
            comptime ty: []const u8,
            comptime field: []const u8,
            set_to: Value,
        ) EvalError!void {
            const val = try vm.stack.peek();
            const ptr = try assertValueIsType(val);
            @field(ptr, field) = @field(set_to, ty);
        }

        fn defaultDisplay(vm: *VM, p: ForeignPtr) void {
            std.debug.print("*<{} {}>", .{ vm.type_table.items[p.ty].name, p.ptr });
        }

        fn defaultEquals(vm: *VM, p1: ForeignPtr, p2: ForeignPtr) bool {
            return p1.ptr == p2.ptr;
        }
    };
}

pub const ForeignType = struct {
    name: []const u8,
    display_fn: fn (*VM, ForeignPtr) void,
    equals_fn: fn (*VM, ForeignPtr, ForeignPtr) bool,
};

pub const Value = union(enum) {
    Int: i32,
    Float: f32,
    Boolean: bool,
    String: usize,
    Symbol: usize,
    Quotation: usize,
    ForeignFnPtr: ForeignFnPtr,
    ForeignPtr: ForeignPtr,
};

pub const Local = struct {
    name: usize,
    value: Value,
};

// main virtual machine
pub const VM = struct {
    const Self = @This();

    allocator: *Allocator,
    symbol_table: ArrayList([]const u8),
    word_table: ArrayList(?Value),
    type_table: ArrayList(ForeignType),
    string_table: ArrayList(Cow(u8)),
    quotation_table: ArrayList(Cow(Literal)),
    stack: Stack(Value),
    locals: Stack(Local),

    pub fn init(allocator: *Allocator) Self {
        var ret = .{
            .allocator = allocator,
            .symbol_table = ArrayList([]const u8).init(allocator),
            .word_table = ArrayList(?Value).init(allocator),
            .type_table = ArrayList(ForeignType).init(allocator),
            .string_table = ArrayList(Cow(u8)).init(allocator),
            .quotation_table = ArrayList(Cow(Literal)).init(allocator),
            .stack = Stack(Value).init(allocator),
            .locals = Stack(Local).init(allocator),
        };
        return ret;
    }

    pub fn deinit(self: *Self) void {
        self.locals.deinit();
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

    // tokenize ===

    fn charIsDelimiter(ch: u8) bool {
        return ascii.isSpace(ch) or ch == ';';
    }

    fn charIsWordValid(ch: u8) bool {
        return ch != '"';
    }

    // TODO can probably have multiline strings
    //        just have to do the thing where leading spaces are removed
    //  "hello
    //   world" should just be "hello\nworld"
    // TODO string escaping
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
                        });
                        state = .Empty;
                        continue;
                    } else if (ch == '\n') {
                        error_info.line_number = line_num;
                        return error.InvalidString;
                    }
                    end += 1;
                },
                .InWord => {
                    if (charIsDelimiter(ch)) {
                        try ret.append(.{
                            .ty = .Word,
                            .str = input[start..(end + 1)],
                        });
                        state = .Empty;
                        continue;
                    } else if (!charIsWordValid(ch)) {
                        error_info.line_number = line_num;
                        return error.InvalidWord;
                    }

                    end += 1;
                },
            }
        }

        switch (state) {
            .InString => {
                error_info.line_number = line_num;
                return error.InvalidString;
            },
            .InWord => {
                try ret.append(.{
                    .ty = .Word,
                    .str = input[start..(end + 1)],
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

        // TODO copy strings on interning
        //  makes sense for if u can generate symbols at runtime
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
                            error_info.line_number = 0;
                            return error.InvalidSymbol;
                        } else {
                            try ret.append(.{ .Symbol = try self.internSymbol(token.str[1..]) });
                        }
                    } else if (std.fmt.parseInt(i32, token.str, 10) catch null) |i| {
                        try ret.append(.{ .Int = i });
                    } else if (try_parse_float and (fl != null)) {
                        try ret.append(.{ .Float = fl.? });
                    } else if (std.mem.eql(u8, token.str, "#t")) {
                        try ret.append(.{ .Boolean = true });
                    } else if (std.mem.eql(u8, token.str, "#f")) {
                        try ret.append(.{ .Boolean = false });
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

    // TODO dont print, return a string
    pub fn nicePrintValue(self: *Self, value: Value) void {
        switch (value) {
            .Int => |val| std.debug.print("{}", .{val}),
            .Float => |val| std.debug.print("{d}f", .{val}),
            .Boolean => |val| {
                const str = if (val) "#t" else "#f";
                std.debug.print("{s}", .{str});
            },
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
            .ForeignFnPtr => |val| std.debug.print("fn({})", .{self.symbol_table.items[val.name]}),
            .ForeignPtr => |ptr| self.type_table.items[ptr.ty].display_fn(self, ptr),
        }
    }

    // TODO this is kindof a weird name
    pub fn equalsValue(self: *Self, a: Value, b: Value) bool {
        if (@as(@TagType(Value), a) == @as(@TagType(Value), b)) {
            return switch (a) {
                .Int => |val| val == b.Int,
                .Float => |val| val == b.Float,
                .Boolean => |val| val == b.Boolean,
                .Symbol => |val| val == b.Symbol,
                // TODO
                .String => false,
                .Quotation => false,
                .ForeignFnPtr => false,
                .ForeignPtr => |ptr| {
                    // TODO maybe move the type check into defaultEquals
                    return ptr.ty == b.ForeignPtr.ty and
                        self.type_table.items[ptr.ty].equals_fn(self, a.ForeignPtr, b.ForeignPtr);
                },
            };
        } else {
            return false;
        }
    }

    pub fn defineForeignType(self: *Self, comptime T: type) Allocator.Error!usize {
        const idx = self.type_table.items.len;
        try self.type_table.append(T.foreignType());
        T.type_id = idx;
        return idx;
    }

    // TODO
    // fn defineWord()

    pub fn evaluateValue(self: *Self, val: Value) EvalError!void {
        switch (val) {
            .Quotation => |id| {
                // TODO handle locals
                try self.eval(self.quotation_table.items[id].get());
            },
            .ForeignFnPtr => |fp| {
                try fp.func(self);
            },
            else => {
                try self.stack.push(val);
            },
        }
    }

    pub fn eval(self: *Self, literals: []const Literal) EvalError!void {
        var quotation_level: usize = 0;
        var q_start: [*]const Literal = undefined;
        var q_ct: usize = 0;

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
                .Int => |i| try self.stack.push(Value{ .Int = i }),
                .Float => |f| try self.stack.push(Value{ .Float = f }),
                .Boolean => |b| try self.stack.push(Value{ .Boolean = b }),
                .String => |str| {
                    const id = self.string_table.items.len;
                    try self.string_table.append(Cow(u8).init(self.allocator, str));
                    try self.stack.push(.{ .String = id });
                },
                .Word => |idx| {
                    const val = self.word_table.items[idx];
                    if (val) |v| {
                        try self.evaluateValue(v);
                    } else {
                        error_info.word_not_found = self.symbol_table.items[idx];
                        return error.WordNotFound;
                    }
                },
                .Symbol => |idx| try self.stack.push(Value{ .Symbol = idx }),
                .QuoteOpen, .QuoteClose => {
                    return error.InternalError;
                },
            }
        }
    }
};
