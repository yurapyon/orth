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

// TODO memoize words so they dont have to be looked up over and over?

// char type? could just use ints
// hex ints
// int parser
// float parser

// vecs and maps, etc can be typed pointers
// rather than being built into Value

// just use a numer type rather than floats and ints?

// errors ===

pub const error_info = struct {
    pub var line_number: usize = undefined;
    pub var word_not_found: []const u8 = undefined;
};

pub const TokenizeError = error{
    InvalidString,
    InvalidWord,
} || Allocator.Error;

pub const ParseError = error{InvalidSymbol} || Allocator.Error;

pub const StackError = error{
    StackOverflow,
    StackUnderflow,
    OutOfBounds,
} || Allocator.Error;

pub const EvalError = error{
    WordNotFound,
    QuotationUnderflow,
    TypeError,
    Panic,
    InternalError,
} || StackError || Allocator.Error;

// tokenize ===

// TODO tokenize with line numbers, for error reporting from parser
pub const Token = struct {
    pub const Type = enum {
        String,
        Word,
    };

    ty: Type,
    str: []const u8
};

pub fn charIsDelimiter(ch: u8) bool {
    return ascii.isSpace(ch) or ch == ';';
}

pub fn charIsWordValid(ch: u8) bool {
    return ch != '"';
}

// TODO can probably have multiline strings
//        just have to do the thing where leading spaces are removed
//  "hello
//   world" should just be "hello\nworld"
// TODO string escaping

pub fn tokenize(allocator: *Allocator, input: []const u8) TokenizeError!ArrayList(Token) {
    const State = enum {
        Empty,
        InComment,
        InString,
        InWord,
    };

    var state: State = .Empty;
    var start: usize = 0;
    var end: usize = 0;

    var ret = ArrayList(Token).init(allocator);
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

//;

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

pub const Literal = union(enum) {
    const Self = @This();

    Int: i32,
    Float: f32,
    Boolean: bool,
    String: usize,
    Word: usize,
    Symbol: usize,
    QuoteOpen,
    QuoteClose,

    pub fn nicePrint(self: Self, string_table: []const []const u8) void {
        switch (self) {
            .Int => |val| std.debug.print("{}i", .{val}),
            .Float => |val| std.debug.print("{d}f", .{val}),
            .Boolean => |val| {
                const str = if (val) "#t" else "#f";
                std.debug.print("{s}", .{str});
            },
            .String => |val| std.debug.print("\"{}\"", .{string_table[val]}),
            .Word => |val| std.debug.print("{}", .{string_table[val]}),
            .Symbol => |val| std.debug.print(":{}", .{string_table[val]}),
            .QuoteOpen => std.debug.print("{{", .{}),
            .QuoteClose => std.debug.print("}}", .{}),
        }
    }
};

pub const ForeignFn = fn (vm: *VM) EvalError!void;

pub const ForeignFnPtr = struct {
    name: usize,
    func: ForeignFn,
};

// TODO maybe rename to ForeignPtr
pub const TypedPtr = struct {
    pub const Ptr = opaque {};
    ty: usize,
    ptr: *Ptr,
};

// these should be in envs
// Foreign types can be values
pub const ForeignType = struct {
    const Self = @This();

    name: usize,
    display_fn: fn (*VM, TypedPtr) void = defaultDisplay,
    equals_fn: fn (*VM, TypedPtr, TypedPtr) bool = defaultEquals,

    // TODO think abt doing genGetter genSetter etc
    //   return a struct{fn setter()void}.setter
    //   type checking is harder though

    pub fn genHelper(comptime T: type) type {
        const name_str = @typeName(T);

        return struct {
            const Self_ = @This();

            var name_id: usize = undefined;

            pub fn internName(vm: *VM) Allocator.Error!usize {
                Self_.name_id = try vm.internString(name_str);
                return Self_.name_id;
            }

            pub fn make(vm: *VM) EvalError!void {
                var obj = try vm.allocator.create(T);
                try vm.stack.push(.{
                    .TypedPtr = .{
                        .ty = Self_.name_id,
                        .ptr = @ptrCast(*TypedPtr.Ptr, obj),
                    },
                });
            }

            pub fn free(vm: *VM) EvalError!void {
                const val = try vm.stack.pop();
                try val.assertType(&[_]@TagType(Value){.TypedPtr});

                if (val.TypedPtr.ty != Self_.name_id) {
                    return error.TypeError;
                } else {
                    const t_ptr = @ptrCast(*T, @alignCast(@alignOf(T), val.TypedPtr.ptr));
                    vm.allocator.destroy(t_ptr);
                }
            }

            pub fn get(vm: *VM, comptime ty: []const u8, comptime field: []const u8) EvalError!void {
                const val = try vm.stack.pop();
                try val.assertType(&[_]@TagType(Value){.TypedPtr});

                if (val.TypedPtr.ty != Self_.name_id) {
                    return error.TypeError;
                } else {
                    const t_ptr = @ptrCast(*T, @alignCast(@alignOf(T), val.TypedPtr.ptr));
                    try vm.stack.push(@unionInit(Value, ty, @field(t_ptr, field)));
                }
            }

            pub fn set(vm: *VM, comptime ty: []const u8, comptime field: []const u8, set_to: Value) EvalError!void {
                const val = try vm.stack.peek();
                try val.assertType(&[_]@TagType(Value){.TypedPtr});
                if (val.TypedPtr.ty != Self_.name_id) {
                    return error.TypeError;
                } else {
                    const t_ptr = @ptrCast(*T, @alignCast(@alignOf(T), val.TypedPtr.ptr));
                    @field(t_ptr, field) = @field(set_to, ty);
                }
            }
        };
    }

    pub fn defaultDisplay(vm: *VM, ptr: TypedPtr) void {
        std.debug.print("*<{} {}>", .{ vm.string_table.items[ptr.ty], ptr.ptr });
    }

    pub fn defaultEquals(vm: *VM, p1: TypedPtr, p2: TypedPtr) bool {
        // TODO
        // note, at this point, vm shouldve already checked obvious equality factors
        //   like that the types are the same
        // defaultEquals should return wether or not the pointers are the same
        return false;
    }
};

// TODO
// vm should have log/print functions or something
//   so u can control where vm messages get printed
//   integrate this into nicePrint functions

// TODO
//   values should not have to be 'cloned'
//     they should all be pointers if they have data somewhere
// could use reference counting for memory management
// being on the stack or in an env counts as a reference
// could do manual memory management but i imagine that would get hard

pub const Value = union(enum) {
    const Self = @This();

    Int: i32,
    Float: f32,
    Boolean: bool,
    Symbol: usize,
    Quotation: ArrayList(Literal),
    ForeignFnPtr: ForeignFnPtr,
    TypedPtr: TypedPtr,
    Vec: *ArrayList(Value),

    // String: ArrayList(u8),
    // TODO make this a *ArrayList
    // Record: Record,

    // Env: Env,

    // TODO dont take a slice here
    pub fn assertType(self: Self, comptime accepted_types: []const @TagType(Value)) EvalError!void {
        var is_ok = false;
        for (accepted_types) |ty| {
            if (@as(@TagType(Value), self) == ty) {
                is_ok = true;
            }
        }
        if (!is_ok) return error.TypeError;
    }

    pub fn equals(self: Self, other: Self) bool {
        if (@as(@TagType(Self), self) == @as(@TagType(Self), other)) {
            return switch (self) {
                .Int => |val| val == other.Int,
                .Float => |val| val == other.Float,
                .Boolean => |val| val == other.Boolean,
                .Symbol => |val| val == other.Symbol,
                .Quotation => false,
                .ForeignFnPtr => false,
                // TODO
                .TypedPtr => false,
                .Vec => false,
            };
        } else {
            return false;
        }
    }

    // TODO dont print, return a string
    // if type is a typed ptr, look for a print function
    //    or, dont do this and just have print funcitons be part of the lib the ptr is from
    pub fn nicePrint(self: Self, string_table: []const []const u8) void {
        switch (self) {
            .Int => |val| std.debug.print("{}i", .{val}),
            .Float => |val| std.debug.print("{d}f", .{val}),
            .Boolean => |val| {
                const str = if (val) "#t" else "#f";
                std.debug.print("{s}", .{str});
            },
            .Symbol => |val| std.debug.print(":{}", .{string_table[val]}),
            .Quotation => |val| {
                std.debug.print("q{{ ", .{});
                for (val.items) |lit| {
                    lit.nicePrint(string_table);
                    std.debug.print(" ", .{});
                }
                std.debug.print("}}", .{});
            },
            .ForeignFnPtr => |val| std.debug.print("fn({})", .{string_table[val.name]}),

            // TODO
            .TypedPtr => |tp| {
                std.debug.print("*<{} {}>", .{ string_table[tp.ty], tp.ptr });
            },
            .Vec => |val| {
                std.debug.print("v[ ", .{});
                for (val.items) |v| {
                    v.nicePrint(string_table);
                    std.debug.print(" ", .{});
                }
                std.debug.print("]", .{});
            },
        }
    }
};

// interned strings could be in the env
//  but this messes with the idea of just using a usize for ids

pub const Env = struct {
    const Self = @This();

    type_table: AutoHashMap(usize, ForeignType),
    table: AutoHashMap(usize, Value),

    pub fn init(allocator: *Allocator) Self {
        return .{
            .type_table = AutoHashMap(usize, ForeignType).init(allocator),
            .table = AutoHashMap(usize, Value).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.type_table.deinit();
        // TODO free values
        self.table.deinit();
    }

    //;

    // TODO rename to insertValue and getValue
    pub fn insert(self: *Self, id: usize, val: Value) Allocator.Error!void {
        try self.table.put(id, val);
    }

    pub fn get(self: Self, id: usize) ?Value {
        return self.table.get(id);
    }

    pub fn insertForeignType(self: *Self, id: usize, ty: ForeignType) Allocator.Error!void {
        try self.type_table.put(id, ty);
    }

    // TODO having to use the id here is kinda clunky
    pub fn getForeignType(self: Self, id: usize) ?ForeignType {
        return self.type_table.get(id);
    }
};

pub const Local = struct {
    name: usize,
    value: Value,
};

// main virtual machine
pub const VM = struct {
    const Self = @This();

    allocator: *Allocator,

    // parse
    string_table: ArrayList([]const u8),

    // eval
    stack: Stack(Value),
    locals: Stack(Local),
    envs: Stack(Env),

    pub fn init(allocator: *Allocator) Allocator.Error!Self {
        var ret = .{
            .allocator = allocator,
            .string_table = ArrayList([]const u8).init(allocator),
            .stack = Stack(Value).init(allocator),
            .locals = Stack(Local).init(allocator),
            .envs = Stack(Env).init(allocator),
        };
        try ret.envs.push(Env.init(allocator));
        return ret;
    }

    pub fn deinit(self: *Self) void {
        for (self.envs.data.items) |env| {
            env.deinit();
        }
        self.envs.deinit();
        self.locals.deinit();
        self.stack.deinit();
        self.string_table.deinit();
    }

    //;

    pub fn internString(self: *Self, str: []const u8) Allocator.Error!usize {
        for (self.string_table.items) |st_str, i| {
            if (std.mem.eql(u8, str, st_str)) {
                return i;
            }
        }

        // TODO copy strings on interning
        const idx = self.string_table.items.len;
        try self.string_table.append(str);
        return idx;
    }

    pub fn parse(self: *Self, tokens: []const Token) ParseError!ArrayList(Literal) {
        var ret = ArrayList(Literal).init(self.allocator);

        for (tokens) |token| {
            switch (token.ty) {
                .String => {
                    try ret.append(.{ .String = try self.internString(token.str) });
                },
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
                            try ret.append(.{ .Symbol = try self.internString(token.str[1..]) });
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
                        try ret.append(.{ .Word = try self.internString(token.str) });
                    }
                },
            }
        }

        return ret;
    }

    pub fn envLookup(self: *Self, name_idx: usize, start_idx: usize) StackError!?Value {
        var i: usize = start_idx;
        while (i < self.envs.data.items.len) : (i += 1) {
            if ((try self.envs.index(i)).get(name_idx)) |val| {
                return val;
            }
        }
        return null;
    }

    pub fn evaluateValue(self: *Self, val: Value) EvalError!void {
        switch (val) {
            .Quotation => |lits| {
                // TODO handle quotation local envs
                //   handle env stacks
                try self.eval(lits.items);
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
        var quotation_buf = ArrayList(Literal).init(self.allocator);

        for (literals) |lit| {
            switch (lit) {
                .QuoteOpen => {
                    quotation_level += 1;
                    if (quotation_level == 1) {
                        quotation_buf.items.len = 0;
                        continue;
                    }
                },
                .QuoteClose => {
                    if (quotation_level == 0) {
                        return error.QuotationUnderflow;
                    }
                    quotation_level -= 1;
                    if (quotation_level == 0) {
                        var cloned = try ArrayList(Literal).initCapacity(self.allocator, quotation_buf.items.len);
                        cloned.appendSliceAssumeCapacity(quotation_buf.items);
                        try self.stack.push(.{ .Quotation = cloned });
                        continue;
                    }
                },
                else => {},
            }

            if (quotation_level > 0) {
                try quotation_buf.append(lit);
                continue;
            }

            switch (lit) {
                .Int => |i| try self.stack.push(Value{ .Int = i }),
                .Float => |f| try self.stack.push(Value{ .Float = f }),
                .Boolean => |b| try self.stack.push(Value{ .Boolean = b }),
                .String => |idx| {
                    // TODO
                },
                .Word => |idx| {
                    const val = try self.envLookup(idx, 0);
                    if (val) |v| {
                        try self.evaluateValue(v);
                    } else {
                        error_info.word_not_found = self.string_table.items[idx];
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
