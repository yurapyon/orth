const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

//;

// stack 0 is top

// display is human readable
// write is machine readable

// once you parse something to values
//   you can get rid of the original text string
// values returned from parse should stay around
//   for the life of the thread thats running them
//   the thread doesnt copy values in order to run them

//;

// envs
//  do it c style
//  have ways to load new words into the vm from a hashtable
//    with renaming, excluding
//  vm word_table is the global lookup table for all words in the session

// unicode is currently not supported but i would like to have it in the future
//   shouldnt be hard
//     unicode chars
//     string_indent need to be updated

// records are vectors
//   u wont get the same level of type checking
//   but if you can generate symbols and quotations at runtime
//     records can easily be made

// TODO need
// repl
//   load and read files
//   probably use a scheduler thing
// error reporting
//   use error_info
//   stack trace thing
//   parse with column number/word number somehow
//     use line_num in eval code
// should vecs be callable
//   having quoations as a separate type is kindof annoying
// better int parser
//   hex ints
// better float parser
//   allow syntax like 1234f
// index stack at n to drop or dup

// TODO want
// certain things cant be symbols
//   because symbols are what you use to name functions and stuff
//   wait for better float and int parser
//   symbols can't have spaces
//     what about string>symbol ?
// ffi threads
//   cooperative multithreading built into vm ?
//     yeild and resume
// parser
//   multiline comments?
//     could use ( )
// some type of define-struct thing, writen w orth

// TODO QOL
// maybe make 'and' and 'or' work like lua ?
//   are values besides #t and #f able to work in places where booleans are accepted
//   usually this is because everything is nullable, but i dont really want that in orth
// vm should have log/print functions or something
//     so u can control where vm messages get printed
//     integrate this into nicePrint functions
//   if nice print is supposed to return strings then idk
//   nicePrint fns take a zig Writer
// zig errors
//   put in 'catch unreachable' on stack pops/indexes that cant fail
//     lib is checked, builtins should be checked
//     if you pop off the stack and instantly push something else, you wont have memory errors
//     its probably not even worth it to do this
// parser
//   could do multiline strings like zig

//;

pub const StackError = error{
    StackOverflow,
    StackUnderflow,
    OutOfBounds,
} || Allocator.Error;

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

pub const StringFixer = struct {
    const Self = @This();

    const Error = error{InvalidStringEscape};

    str: []const u8,
    indent: usize,

    first_line: bool,
    char_at: usize,
    line_at: usize,
    col_at: usize,
    in_escape: bool,

    pub fn init(str: []const u8, indent: usize) Self {
        return .{
            .str = str,
            .indent = indent,
            .first_line = true,
            .char_at = 0,
            .line_at = 0,
            .col_at = 0,
            .in_escape = false,
        };
    }

    pub fn reset(self: *Self) void {
        self.* = init(self.str, self.indent);
    }

    // TODO unicode
    // escapes like \#space , which use char escaper
    pub fn parseStringEscape(ch: u8) Error!u8 {
        return switch (ch) {
            'n' => '\n',
            't' => '\t',
            '0' => 0,
            '\\', '"' => ch,
            else => error.InvalidStringEscape,
        };
    }

    pub fn next(self: *Self) Error!?u8 {
        while (self.char_at < self.str.len) {
            const ch = self.str[self.char_at];
            self.char_at += 1;

            var ret: u8 = undefined;

            if (self.in_escape) {
                self.in_escape = false;
                ret = try parseStringEscape(ch);
            } else {
                if (ch == '\\') {
                    self.in_escape = true;
                    continue;
                }

                if (self.first_line) {
                    ret = ch;
                } else {
                    if (self.col_at >= self.indent) {
                        ret = ch;
                    } else {
                        continue;
                    }
                }
            }

            if (ch == '\n') {
                self.first_line = false;
                self.line_at += 1;
                self.col_at = 0;
            } else {
                self.col_at += 1;
            }

            return ret;
        }

        return null;
    }
};

//;

pub const Token = struct {
    pub const Data = union(enum) {
        String: struct {
            str: []const u8,
            indent: usize,
        },
        CharEscape: u8,
        Symbol: []const u8,
        Word: []const u8,
    };

    data: Data,
};

pub const Tokenizer = struct {
    const Self = @This();

    pub const Error = error{
        InvalidString,
        UnfinishedString,
        InvalidCharEscape,
        InvalidSymbol,
        InvalidWord,
    };

    // TODO use this correctly
    pub const ErrorInfo = struct {
        line_number: usize,
    };

    pub const State = enum {
        Empty,
        InComment,
        InString,
        MaybeInEscape,
        InEscape,
        InSymbol,
        InWord,
    };

    buf: []const u8,

    state: State,
    error_info: ErrorInfo,

    line_at: usize,
    col_at: usize,

    start_char: usize,
    end_char: usize,
    in_string_escape: bool,
    string_indent: usize,

    pub fn init(buf: []const u8) Self {
        return .{
            .buf = buf,
            .state = .Empty,
            .error_info = undefined,
            .line_at = 0,
            .col_at = 0,
            .start_char = 0,
            .end_char = 0,
            .in_string_escape = false,
            .string_indent = 0,
        };
    }

    pub fn charIsWhitespace(ch: u8) bool {
        return ch == ' ' or ch == '\n';
    }

    pub fn charIsDelimiter(ch: u8) bool {
        return charIsWhitespace(ch) or ch == ';';
    }

    pub fn charIsWordValid(ch: u8) bool {
        return ch != '"' and ch != ':';
    }

    pub fn parseCharEscape(str: []const u8) Error!u8 {
        if (str.len == 1) {
            return str[0];
        } else {
            // TODO star, heart
            if (std.mem.eql(u8, str, "space")) {
                return '\n';
            } else if (std.mem.eql(u8, str, "tab")) {
                return '\t';
            } else {
                return error.InvalidCharEscape;
            }
        }
    }

    pub fn next(self: *Self) Error!?Token {
        while (self.end_char < self.buf.len) {
            const ch = self.buf[self.end_char];
            self.end_char += 1;

            if (ch == '\n') {
                self.line_at += 1;
                self.col_at = 0;
            } else {
                self.col_at += 1;
            }

            switch (self.state) {
                .Empty => {
                    if (charIsWhitespace(ch)) {
                        continue;
                    }
                    self.state = switch (ch) {
                        ';' => .InComment,
                        '"' => blk: {
                            self.string_indent = self.col_at;
                            break :blk .InString;
                        },
                        '#' => .MaybeInEscape,
                        ':' => .InSymbol,
                        else => .InWord,
                    };
                    self.start_char = self.end_char - 1;
                },
                .InComment => {
                    if (ch == '\n') {
                        self.state = .Empty;
                    }
                },
                .InString => {
                    if (self.in_string_escape) {
                        _ = StringFixer.parseStringEscape(ch) catch {
                            return error.InvalidString;
                        };
                        self.in_string_escape = false;
                    } else {
                        if (ch == '\\') {
                            self.in_string_escape = true;
                        } else if (ch == '"') {
                            self.state = .Empty;
                            return Token{
                                .data = .{
                                    .String = .{
                                        .str = self.buf[(self.start_char + 1)..(self.end_char - 1)],
                                        .indent = self.string_indent,
                                    },
                                },
                            };
                        }
                    }
                },
                .MaybeInEscape => {
                    self.state = if (ch == '\\') .InEscape else .InWord;
                },
                .InEscape => {
                    if (charIsDelimiter(ch)) {
                        self.state = .Empty;

                        return Token{
                            .data = .{
                                .CharEscape = try parseCharEscape(
                                    self.buf[(self.start_char + 2)..(self.end_char - 1)],
                                ),
                            },
                        };
                    }
                },
                .InSymbol => {
                    if (charIsDelimiter(ch)) {
                        self.state = .Empty;
                        const name = self.buf[(self.start_char + 1)..(self.end_char - 1)];
                        if (name.len == 0) return error.InvalidSymbol;
                        return Token{
                            .data = .{ .Symbol = name },
                        };
                    } else if (!charIsWordValid(ch)) {
                        self.error_info.line_number = self.line_at - 1;
                        return error.InvalidSymbol;
                    }
                },
                .InWord => {
                    if (charIsDelimiter(ch)) {
                        self.state = .Empty;
                        return Token{
                            .data = .{
                                .Word = self.buf[self.start_char..(self.end_char - 1)],
                            },
                        };
                    } else if (!charIsWordValid(ch)) {
                        self.error_info.line_number = self.line_at - 1;
                        return error.InvalidWord;
                    }
                },
            }
        } else if (self.end_char == self.buf.len) {
            switch (self.state) {
                .Empty,
                .InComment,
                => {
                    return null;
                },
                .InString => {
                    self.error_info.line_number = self.line_at - 1;
                    return error.UnfinishedString;
                },
                .MaybeInEscape => return error.InvalidCharEscape,
                .InEscape => {
                    self.state = .Empty;
                    return Token{
                        .data = .{
                            .CharEscape = try parseCharEscape(
                                self.buf[(self.start_char + 2)..self.end_char],
                            ),
                        },
                    };
                },
                .InSymbol => {
                    self.state = .Empty;
                    const name = self.buf[(self.start_char + 1)..self.end_char];
                    if (name.len == 0) return error.InvalidSymbol;
                    return Token{
                        .data = .{ .Symbol = name },
                    };
                },
                .InWord => {
                    self.state = .Empty;
                    return Token{
                        .data = .{
                            .Word = self.buf[self.start_char..self.end_char],
                        },
                    };
                },
            }
        }

        unreachable;
    }
};

//;

pub const FFI_Fn = struct {
    pub const Function = fn (*Thread) Thread.Error!void;

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
    Boolean: bool,
    Sentinel,
    String: []const u8,
    Word: usize,
    Symbol: usize,
    Quotation: []const Value,
    FFI_Fn: FFI_Fn,
    FFI_Ptr: FFI_Ptr,
};

//;

pub const FFI_Type = struct {
    const Self = @This();

    name: []const u8 = "ffi",
    call_fn: ?fn (*Thread, FFI_Ptr) []const Value = null,
    display_fn: fn (*Thread, FFI_Ptr) void = defaultDisplay,
    equivalent_fn: fn (*Thread, FFI_Ptr, Value) bool = defaultEquivalent,
    dup_fn: fn (*VM, FFI_Ptr) FFI_Ptr = defaultDup,
    drop_fn: fn (*VM, FFI_Ptr) void = defaultDrop,

    name_id: usize = undefined,
    type_id: usize = undefined,

    fn defaultDisplay(t: *Thread, ptr: FFI_Ptr) void {
        std.debug.print("*<{} {}>", .{
            t.vm.type_table[ptr.type_id].name,
            ptr.ptr,
        });
    }

    fn defaultEquivalent(t: *Thread, ptr: FFI_Ptr, val: Value) bool {
        return false;
    }

    fn defaultDup(t: *VM, ptr: FFI_Ptr) FFI_Ptr {
        return ptr;
    }

    fn defaultDrop(t: *VM, ptr: FFI_Ptr) void {}

    //;

    pub fn makePtr(self: Self, ptr: anytype) FFI_Ptr {
        return .{
            .type_id = self.type_id,
            .ptr = @ptrCast(*FFI_Ptr.Ptr, ptr),
        };
    }

    pub fn checkType(self: Self, ptr: FFI_Ptr) Thread.Error!void {
        if (ptr.type_id != self.type_id) {
            return error.TypeError;
        }
    }
};

pub const ReturnValue = struct {
    value: Value,
    restore_ct: usize,
    //TODO "callee was callable" or something
    has_callable: bool,
};

pub const VM = struct {
    const Self = @This();

    pub const BuiltInIds = enum {
        QuoteOpen,
        QuoteClose,
        Int,
        Float,
        Char,
        Boolean,
        Sentinel,
        String,
        Word,
        Symbol,
        Quotation,
        FFI_Fn,
        FFI_Ptr,
    };

    pub const ErrorInfo = struct {
        word_not_found: []const u8,
    };

    allocator: *Allocator,
    error_info: ErrorInfo,

    symbol_table: ArrayList([]const u8),
    word_table: ArrayList(?Value),
    docs_table: ArrayList(?[]const u8),
    type_table: ArrayList(*const FFI_Type),

    string_literals: ArrayList([]const u8),

    pub fn init(allocator: *Allocator) Allocator.Error!Self {
        var ret = Self{
            .allocator = allocator,
            .error_info = undefined,

            .symbol_table = ArrayList([]const u8).init(allocator),
            .word_table = ArrayList(?Value).init(allocator),
            .docs_table = ArrayList(?[]const u8).init(allocator),
            .type_table = ArrayList(*const FFI_Type).init(allocator),

            .string_literals = ArrayList([]const u8).init(allocator),
        };
        std.debug.assert(@enumToInt(BuiltInIds.QuoteOpen) == try ret.internSymbol("{"));
        std.debug.assert(@enumToInt(BuiltInIds.QuoteClose) == try ret.internSymbol("}"));
        std.debug.assert(@enumToInt(BuiltInIds.Int) == try ret.internSymbol("int"));
        std.debug.assert(@enumToInt(BuiltInIds.Float) == try ret.internSymbol("float"));
        std.debug.assert(@enumToInt(BuiltInIds.Char) == try ret.internSymbol("char"));
        std.debug.assert(@enumToInt(BuiltInIds.Boolean) == try ret.internSymbol("boolean"));
        std.debug.assert(@enumToInt(BuiltInIds.Sentinel) == try ret.internSymbol("sentinel"));
        std.debug.assert(@enumToInt(BuiltInIds.String) == try ret.internSymbol("string"));
        std.debug.assert(@enumToInt(BuiltInIds.Word) == try ret.internSymbol("word"));
        std.debug.assert(@enumToInt(BuiltInIds.Symbol) == try ret.internSymbol("symbol"));
        std.debug.assert(@enumToInt(BuiltInIds.Quotation) == try ret.internSymbol("quotation"));
        std.debug.assert(@enumToInt(BuiltInIds.FFI_Fn) == try ret.internSymbol("ffi-fn"));
        std.debug.assert(@enumToInt(BuiltInIds.FFI_Ptr) == try ret.internSymbol("ffi-ptr"));
        return ret;
    }

    pub fn deinit(self: *Self) void {
        for (self.word_table.items) |val| {
            if (val) |v| {
                self.dropValue(v);
            }
        }

        for (self.string_literals.items) |str| {
            self.allocator.free(str);
        }
        self.string_literals.deinit();
        for (self.docs_table.items) |maybe_doc| {
            if (maybe_doc) |doc| {
                self.allocator.free(doc);
            }
        }
        self.docs_table.deinit();
        self.type_table.deinit();
        self.word_table.deinit();
        for (self.symbol_table.items) |sym| {
            self.allocator.free(sym);
        }
        self.symbol_table.deinit();
    }

    // parse ===

    pub fn internSymbol(self: *Self, str: []const u8) Allocator.Error!usize {
        for (self.symbol_table.items) |st_str, i| {
            if (std.mem.eql(u8, str, st_str)) {
                return i;
            }
        }

        const idx = self.symbol_table.items.len;
        try self.symbol_table.append(try self.allocator.dupe(u8, str));
        try self.word_table.append(null);
        try self.docs_table.append(null);
        return idx;
    }

    pub fn parse(self: *Self, token: Token) Allocator.Error!Value {
        switch (token.data) {
            .String => |str_data| {
                var ct: usize = 0;
                var fixer = StringFixer.init(str_data.str, str_data.indent);
                while (fixer.next() catch unreachable) |_| {
                    ct += 1;
                }

                const buf = try self.allocator.alloc(u8, ct);
                fixer.reset();
                ct = 0;
                while (fixer.next() catch unreachable) |ch| {
                    buf[ct] = ch;
                    ct += 1;
                }

                try self.string_literals.append(buf);

                return Value{ .String = buf };
            },
            .CharEscape => |ch| {
                return Value{ .Char = ch };
            },
            .Symbol => |sym| {
                return Value{ .Symbol = try self.internSymbol(sym) };
            },
            .Word => |word| {
                const try_parse_float =
                    !std.mem.eql(u8, word, "+") and
                    !std.mem.eql(u8, word, "-") and
                    !std.mem.eql(u8, word, ".");
                const fl = std.fmt.parseFloat(f32, word) catch null;

                if (std.fmt.parseInt(i32, word, 10) catch null) |i| {
                    return Value{ .Int = i };
                } else if (try_parse_float and (fl != null)) {
                    return Value{ .Float = fl.? };
                } else {
                    return Value{ .Word = try self.internSymbol(word) };
                }
            },
        }
    }

    // eval ===

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

    //;

    pub fn installFFI_Type(self: *Self, ty: *FFI_Type) Allocator.Error!void {
        const idx = self.type_table.items.len;
        ty.type_id = idx;
        ty.name_id = try self.internSymbol(ty.name);
        try self.type_table.append(ty);
    }

    pub fn defineWord(self: *Self, name: []const u8, value: Value, doc_string: ?[]const u8) Allocator.Error!void {
        const idx = try self.internSymbol(name);
        // TODO dup value here?
        self.word_table.items[idx] = value;
        self.docs_table.items[idx] = if (doc_string) |str| try self.allocator.dupe(u8, str) else null;
    }
};

pub const Thread = struct {
    const Self = @This();

    pub const Error = error{
        WordNotFound,
        TypeError,
        DivideByZero,
        NegativeDenominator,
        Panic,
        InvalidReturnValue,
        InternalError,
    } || StackError || Allocator.Error;

    // TODO use this
    pub const ErrorInfo = struct {
        line_number: usize,
        word_not_found: []const u8,
    };

    vm: *VM,
    error_info: ErrorInfo,

    current_execution: []const Value,

    stack: Stack(Value),
    return_stack: Stack(ReturnValue),
    restore_stack: Stack(Value),
    callables_stack: Stack(Value),

    // note: this coud be a Stack([]const Value)
    //   but there is a zig bug
    //   just going to use a Value that will always be a Value.Quotation
    q_stack: Stack(Value),

    pub fn init(vm: *VM, values: []const Value) Self {
        var ret = .{
            .vm = vm,
            .error_info = undefined,

            .current_execution = values,

            .stack = Stack(Value).init(vm.allocator),
            .return_stack = Stack(ReturnValue).init(vm.allocator),
            .restore_stack = Stack(Value).init(vm.allocator),
            .callables_stack = Stack(Value).init(vm.allocator),

            .q_stack = Stack(Value).init(vm.allocator),
        };
        return ret;
    }

    pub fn deinit(self: *Self) void {
        for (self.stack.data.items) |val| {
            self.vm.dropValue(val);
        }
        self.q_stack.deinit();
        self.callables_stack.deinit();
        self.restore_stack.deinit();
        self.return_stack.deinit();
        self.stack.deinit();
    }

    //;

    pub fn nicePrintValue(self: *Self, value: Value) void {
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
            .Symbol => |val| std.debug.print(":{}", .{self.vm.symbol_table.items[val]}),
            .Word => |val| std.debug.print("\\{}", .{self.vm.symbol_table.items[val]}),
            .String => |val| std.debug.print("\"{}\"L", .{val}),
            .Quotation => |q| {
                std.debug.print("q{{ ", .{});
                for (q) |val| {
                    self.nicePrintValue(val);
                    std.debug.print(" ", .{});
                }
                std.debug.print("}}L", .{});
            },
            .FFI_Fn => |val| std.debug.print("fn({})", .{self.vm.symbol_table.items[val.name]}),
            .FFI_Ptr => |ptr| self.vm.type_table.items[ptr.type_id].display_fn(self, ptr),
        }
    }

    //;

    // TODO refactor this and the next fn so the repl can use it
    pub fn evaluateValue(self: *Self, val: Value, restore_ct: usize) Error!void {
        switch (val) {
            .Quotation => |q| {
                // note: TCO
                if (self.current_execution.len > 0 or restore_ct > 0) {
                    try self.return_stack.push(.{
                        .value = .{ .Quotation = self.current_execution },
                        .restore_ct = restore_ct,
                        .has_callable = false,
                    });
                }
                self.current_execution = q;
            },
            .FFI_Fn => |fp| try fp.func(self),
            .FFI_Ptr => |ptr| {
                if (self.vm.type_table.items[ptr.type_id].call_fn) |call_fn| {
                    try self.return_stack.push(.{
                        .value = .{ .Quotation = self.current_execution },
                        .restore_ct = restore_ct,
                        .has_callable = true,
                    });
                    try self.callables_stack.push(self.vm.dupValue(val));
                    self.current_execution = call_fn(self, ptr);
                } else {
                    try self.stack.push(self.vm.dupValue(val));
                }
            },
            else => try self.stack.push(self.vm.dupValue(val)),
        }
    }

    pub fn eval(self: *Self) Error!bool {
        while (self.current_execution.len != 0) {
            var value = self.current_execution[0];

            self.current_execution.ptr += 1;
            self.current_execution.len -= 1;

            switch (value) {
                .Word => |idx| {
                    if (idx == @enumToInt(VM.BuiltInIds.QuoteOpen)) {
                        try self.q_stack.push(.{ .Quotation = self.current_execution });
                    } else if (idx == @enumToInt(VM.BuiltInIds.QuoteClose)) {
                        // TODO if this pop doesnt work, return error.QuotationStackUnderflow
                        var q = try self.q_stack.pop();
                        if (self.q_stack.data.items.len == 0) {
                            q.Quotation.len -= self.current_execution.len + 1;
                            try self.stack.push(q);
                        }
                    } else {
                        if (self.q_stack.data.items.len > 0) {
                            return true;
                        } else {
                            const found_word = self.vm.word_table.items[idx];
                            if (found_word) |v| {
                                try self.evaluateValue(v, 0);
                            } else {
                                self.error_info.word_not_found = self.vm.symbol_table.items[idx];
                                return error.WordNotFound;
                            }
                        }
                    }
                },
                else => |val| {
                    if (self.q_stack.data.items.len == 0) {
                        try self.stack.push(val);
                    }
                },
            }

            return true;
        }

        if (self.return_stack.data.items.len > 0) {
            const rv = self.return_stack.pop() catch unreachable;
            if (rv.restore_ct == std.math.maxInt(usize)) {
                return error.InvalidReturnValue;
            }
            if (rv.has_callable) {
                self.vm.dropValue(self.callables_stack.pop() catch unreachable);
            }

            var i: usize = 0;
            while (i < rv.restore_ct) : (i += 1) {
                try self.stack.push(self.restore_stack.pop() catch unreachable);
            }
            self.current_execution = rv.value.Quotation;
            return true;
        } else {
            return false;
        }
    }
};
