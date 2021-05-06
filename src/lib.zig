const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ascii = std.ascii;

//;

// stack 0 is top

// records are vectors
//   u wont get the same level of type checking
//   but if you can generate symbols and quotations at runtime
//     records can easily be made

// display is human readable
// write is machine readable

// TODO need
// parser
//   char type
//     do them like #\A #\b etc
//     #\ is an escaper thing
//     how to do unicode?
//   strings
//     multiline strings
//       do the thing where leading spaces are removed
//       "hello
//        world" should just be "hello\nworld"
//     string escaping
//   multiline comments?
//     would be nice
//     could use ( )
// memory management
//   currently values returned from parser need to stay around while vm is evaluating
//     would be nice if this wasnt the case ?
// zig errors
//   put in 'catch unreachable' on stack pops/indexes that cant fail
// error reporting
//   stack trace thing
//   parse with column number/word number somehow
//     use line_num in eval code
// ffi quotations

// TODO want
// namespaces / envs would be nice but have to think abt how they should work
// tail call optimization
// maybe make 'and' and 'or' work like lua ?
//   are values besides #t and #f able to work in places where booleans are accepted
//   usually this is because everything is nullable, but i dont really want that in orth

// TODO QOL
// better int parser
//   hex ints
// better float parser
//   allow syntax like 1234f
// certain things cant be symbols
//   because symbols are what you use to name functions and stuff
// vm should have log/print functions or something
//     so u can control where vm messages get printed
//     integrate this into nicePrint functions
//   if nice print is supposed to return strings then idk
//   nicePrint fns take a zig Writer

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

pub const ParseError = error{
    InvalidString,
    InvalidWord,
    InvalidSymbol,
    QuotationUnderflow,
    UnfinishedQuotation,
} || Allocator.Error;

pub const EvalError = error{
    WordNotFound,
    TypeError,
    DivideByZero,
    NegativeDenominator,
    Panic,
    InternalError,
} || StackError || Allocator.Error;

//;

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

//;

pub const FFI_Fn = struct {
    pub const Function = fn (vm: *VM) EvalError!void;

    name: usize,
    func: Function,
};

pub const FFI_Ptr = struct {
    const Self = @This();

    pub const Ptr = opaque {};

    type_id: usize,
    ptr: *Ptr,

    pub fn cast(self: Self, comptime T: type) *T {
        return @ptrCast(*T, @alignCast(@alignOf(T), self.ptr));
    }
};

pub const Value = union(enum) {
    Int: i64,
    Float: f64,
    Char: u8,
    // TODO unicode
    Boolean: bool,
    Sentinel,
    String: []const u8,
    Word: usize,
    Symbol: usize,
    Quotation: []const Value,
    FFI_Fn: FFI_Fn,
    FFI_Ptr: FFI_Ptr,
    QuoteOpen,
    QuoteClose,
};

//;

pub const FFI_Type = struct {
    const Self = @This();

    type_id: usize = undefined,

    call_fn: ?fn (*VM, FFI_Ptr) void = null,
    display_fn: fn (*VM, FFI_Ptr) void = defaultDisplay,
    equals_fn: fn (*VM, FFI_Ptr, FFI_Ptr) bool = defaultEquals,
    dup_fn: fn (*VM, FFI_Ptr) FFI_Ptr = defaultDup,
    drop_fn: fn (*VM, FFI_Ptr) void = defaultDrop,

    fn defaultDisplay(vm: *VM, ptr: FFI_Ptr) void {
        std.debug.print("*<{} {}>", .{
            ptr.type_id,
            ptr.ptr,
        });
    }

    fn defaultEquals(vm: *VM, ptr1: FFI_Ptr, ptr2: FFI_Ptr) bool {
        return ptr1.type_id == ptr2.type_id and
            ptr1.ptr == ptr2.ptr;
    }

    fn defaultDup(vm: *VM, ptr: FFI_Ptr) FFI_Ptr {
        return ptr;
    }

    fn defaultDrop(vm: *VM, ptr: FFI_Ptr) void {
        return true;
    }

    //;

    pub fn makePtr(self: Self, ptr: anytype) FFI_Ptr {
        return .{
            .type_id = self.type_id,
            .ptr = @ptrCast(*FFI_Ptr.Ptr, ptr),
        };
    }

    pub fn checkType(self: Self, ptr: FFI_Ptr) EvalError!void {
        if (ptr.type_id != self.type_id) {
            return error.TypeError;
        }
    }
};

pub const ReturnValue = struct {
    value: Value,
    restore_ct: usize,
};

pub const VM = struct {
    const Self = @This();

    allocator: *Allocator,
    error_info: ErrorInfo,

    symbol_table: ArrayList([]const u8),
    word_table: ArrayList(?Value),
    type_table: ArrayList(*const FFI_Type),

    current_execution: []const Value,

    stack: Stack(Value),
    return_stack: Stack(ReturnValue),
    restore_stack: Stack(Value),

    pub fn init(allocator: *Allocator) Self {
        var ret = .{
            .allocator = allocator,
            .error_info = undefined,

            .symbol_table = ArrayList([]const u8).init(allocator),
            .word_table = ArrayList(?Value).init(allocator),
            .type_table = ArrayList(*const FFI_Type).init(allocator),

            .current_execution = undefined,

            .stack = Stack(Value).init(allocator),
            .return_stack = Stack(ReturnValue).init(allocator),
            .restore_stack = Stack(Value).init(allocator),
        };
        return ret;
    }

    pub fn deinit(self: *Self) void {
        for (self.stack.data.items) |val| {
            self.dropValue(val);
        }
        for (self.word_table.items) |val| {
            if (val) |v| {
                self.dropValue(v);
            }
        }
        self.restore_stack.deinit();
        self.return_stack.deinit();
        self.stack.deinit();
        self.type_table.deinit();
        self.word_table.deinit();
        for (self.symbol_table.items) |sym| {
            self.allocator.free(sym);
        }
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

        // _ = try vm.defineForeignType(builtins.Vec.ft);
        // _ = try vm.defineForeignType(builtins.Proto.ft);

        var base_f = try readFile(allocator, "src/base.orth");
        defer allocator.free(base_f);

        const base_toks = try vm.tokenize(base_f);
        defer base_toks.deinit();

        const base_lits = try vm.parse(base_toks.items);
        defer base_lits.deinit();

        try vm.eval(base_lits.items);
    }

    // parse ===

    pub fn charIsDelimiter(ch: u8) bool {
        return ascii.isSpace(ch) or ch == ';';
    }

    pub fn charIsWordValid(ch: u8) bool {
        return ch != '"';
    }

    pub fn internSymbol(self: *Self, str: []const u8) Allocator.Error!usize {
        for (self.symbol_table.items) |st_str, i| {
            if (std.mem.eql(u8, str, st_str)) {
                return i;
            }
        }

        const idx = self.symbol_table.items.len;
        try self.symbol_table.append(try self.allocator.dupe(u8, str));
        try self.word_table.append(null);
        return idx;
    }

    pub fn parseWord(self: *Self, word: []const u8) ParseError!Value {
        var try_parse_float =
            !std.mem.eql(u8, word, "+") and
            !std.mem.eql(u8, word, "-") and
            !std.mem.eql(u8, word, ".");
        const fl = std.fmt.parseFloat(f32, word) catch null;

        if (word[0] == ':') {
            if (word.len == 1) {
                self.error_info.line_number = 0;
                return error.InvalidSymbol;
            } else {
                return Value{ .Symbol = try self.internSymbol(word[1..]) };
            }
        } else if (std.fmt.parseInt(i32, word, 10) catch null) |i| {
            return Value{ .Int = i };
        } else if (try_parse_float and (fl != null)) {
            return Value{ .Float = fl.? };
        } else if (std.mem.eql(u8, word, "{")) {
            return Value{ .QuoteOpen = {} };
        } else if (std.mem.eql(u8, word, "}")) {
            return Value{ .QuoteClose = {} };
        } else {
            return Value{ .Word = try self.internSymbol(word) };
        }
    }

    // TODO could parse these value by value
    pub fn parse(self: *Self, input: []const u8) ParseError!ArrayList(Value) {
        const State = enum {
            Empty,
            InComment,
            InString,
            InWord,
        };

        var state: State = .Empty;
        var start: usize = 0;
        var end: usize = 0;

        var ret = ArrayList(Value).init(self.allocator);
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
                        try ret.append(.{ .String = input[(start + 1)..(end + 1)] });
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
                        const word = input[start..(end + 1)];
                        try ret.append(try self.parseWord(word));
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
                const word = input[start..(end + 1)];
                try ret.append(try self.parseWord(word));
            },
            else => {},
        }

        var q_stack = Stack(usize).init(self.allocator);
        defer q_stack.deinit();

        // TODO combine this with above loop
        // probably skip adding '}' to the return array
        // add sentinels in place of open quotes
        for (ret.items) |value, i| {
            switch (value) {
                .QuoteOpen => {
                    try q_stack.push(i);
                },
                .QuoteClose => {
                    if (q_stack.data.items.len == 0) {
                        return error.QuotationUnderflow;
                    }
                    const q_start = q_stack.pop() catch unreachable;
                    ret.items[q_start] = .{ .Quotation = ret.items[(q_start + 1)..i] };
                },
                else => {},
            }
        }

        if (q_stack.data.items.len > 0) return error.UnfinishedQuotation;

        return ret;
    }

    // eval ===

    pub fn nicePrintValue(self: *Self, value: Value) void {
        switch (value) {
            .Int => |val| std.debug.print("{}", .{val}),
            .Float => |val| std.debug.print("{d}f", .{val}),
            .Char => |val| std.debug.print("{c}", .{val}),
            .Boolean => |val| {
                const str = if (val) "#t" else "#f";
                std.debug.print("{s}", .{str});
            },
            .Sentinel => std.debug.print("#sentinel", .{}),
            .Symbol => |val| std.debug.print(":{}", .{self.symbol_table.items[val]}),
            .Word => |val| std.debug.print("\\{}", .{self.symbol_table.items[val]}),
            .String => |val| std.debug.print("\"{}\"L", .{val}),
            .Quotation => |q| {
                std.debug.print("q{{ ", .{});
                // TODO fix this loop to acct for quotations in quotations
                for (q) |val| {
                    self.nicePrintValue(val);
                    std.debug.print(" ", .{});
                }
                std.debug.print("}}L", .{});
            },
            .FFI_Fn => |val| std.debug.print("fn({})", .{self.symbol_table.items[val.name]}),
            .FFI_Ptr => |ptr| self.type_table.items[ptr.type_id].display_fn(self, ptr),
            .QuoteOpen => std.debug.print("{{", .{}),
            .QuoteClose => std.debug.print("}}", .{}),
        }
    }

    pub fn installFFI_Type(self: *Self, ty: *FFI_Type) Allocator.Error!void {
        const idx = self.type_table.items.len;
        ty.type_id = idx;
        try self.type_table.append(ty);
    }

    pub fn defineWord(self: *Self, name: []const u8, value: Value) Allocator.Error!void {
        const idx = try self.internSymbol(name);
        self.word_table.items[idx] = value;
    }

    pub fn dupValue(self: *Self, val: Value) Value {
        switch (val) {
            .FFI_Ptr => |ptr| return .{
                .FFI_Ptr = self.type_table.items[ptr.type_id].dup_fn(self, ptr),
            },
            else => return val,
        }
    }

    pub fn dropValue(self: *Self, val: Value) void {
        if (val == .FFI_Ptr) {
            const ptr = val.FFI_Ptr;
            self.type_table.items[ptr.type_id].drop_fn(self, ptr);
        }
    }

    pub fn evaluateValue(self: *Self, val: Value, restore_ct: usize) EvalError!void {
        switch (val) {
            .Quotation => |q| {
                try self.return_stack.push(.{
                    .value = .{ .Quotation = self.current_execution },
                    .restore_ct = restore_ct,
                });
                self.current_execution = q;
            },
            .FFI_Fn => |fp| try fp.func(self),
            .FFI_Ptr => |ptr| {
                if (self.type_table.items[ptr.type_id].call_fn) |call_fn| {
                    call_fn(self, ptr);
                } else {
                    try self.stack.push(self.dupValue(val));
                }
            },
            else => try self.stack.push(self.dupValue(val)),
        }
    }

    pub fn eval(self: *Self, values: []const Value) EvalError!void {
        var quotation_level: usize = 0;
        var q_start: [*]const Value = undefined;
        var q_ct: usize = 0;

        self.current_execution = values;

        while (true) {
            while (self.current_execution.len != 0) {
                var value = self.current_execution[0];

                self.current_execution.ptr += 1;
                self.current_execution.len -= 1;

                switch (value) {
                    .Word => |idx| {
                        const found_word = self.word_table.items[idx];
                        if (found_word) |v| {
                            try self.evaluateValue(v, 0);
                        } else {
                            self.error_info.word_not_found = self.symbol_table.items[idx];
                            return error.WordNotFound;
                        }
                    },
                    .Quotation => |q| {
                        try self.stack.push(value);
                        self.current_execution.ptr += q.len + 1;
                        self.current_execution.len -= q.len + 1;
                    },
                    .QuoteOpen, .QuoteClose => return error.InternalError,
                    else => |val| try self.stack.push(val),
                }
            }

            if (self.return_stack.data.items.len > 0) {
                const rv = self.return_stack.pop() catch unreachable;
                var i: usize = 0;
                while (i < rv.restore_ct) : (i += 1) {
                    try self.stack.push(self.restore_stack.pop() catch unreachable);
                }
                self.current_execution = rv.value.Quotation;
            } else {
                break;
            }
        }
    }
};
