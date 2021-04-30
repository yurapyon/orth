const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ascii = std.ascii;
const AutoHashMap = std.AutoHashMap;
const StringHashMap = std.StringHashMap;

//;

// center of the design should be contexts and envs
//  able to parse into an env

// TODO multiline strings

// TODO certain things cant be symbols
//   because symbols are what you use to name functions and stuff

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

// note: tokenizer doesnt copy strings
pub const Tokenizer = struct {
    const Self = @This();

    pub const Error = error{
        InvalidString,
        InvalidWord,
    } || Allocator.Error;

    pub const ErrorInfo = struct {
        err: Error,
        line_num: usize,
    };

    error_info: ErrorInfo,

    pub fn init() Self {
        return .{
            .error_info = undefined,
        };
    }

    pub fn tokenize(
        self: *Self,
        allocator: *Allocator,
        input: []const u8,
    ) Error!ArrayList(Token) {
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
                        self.error_info = .{
                            .err = Error.InvalidString,
                            .line_num = line_num,
                        };
                        return self.error_info.err;
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
                        self.error_info = .{
                            .err = Error.InvalidWord,
                            .line_num = line_num,
                        };
                        return self.error_info.err;
                    }

                    end += 1;
                },
            }
        }

        switch (state) {
            .InString => {
                self.error_info = .{
                    .err = Error.InvalidString,
                    .line_num = line_num,
                };
                return self.error_info.err;
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
};

//;

pub fn Stack_(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Error = error{
            StackOverflow,
            StackUnderflow,
        } || Allocator.Error;

        data: ArrayList(Value),

        pub fn init(allocator: *Allocator) Self {
            return .{
                .data = ArrayList(Value).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            // TODO free values
            self.data.deinit();
        }

        pub fn push(self: *Self, val: Value) Error!void {
            try self.data.append(val);
        }

        pub fn pop(self: *Self) Error!Value {
            if (self.data.items.len == 0) {
                return Error.StackUnderflow;
            }
            var ret = self.data.items[self.data.items.len - 1];
            self.data.items.len -= 1;
            return ret;
        }

        pub fn peek(self: *Self) Error!Value {
            var ret = self.data.items[self.data.items.len - 1];
            return ret;
        }
    };
}

// use a locals stack?

// could have the environment be a stack
//  each value is tagged with a name

pub const LocalEnvItem = struct {
    name: usize,
    value: Value,
};

// main virtual machine
pub const Context_ = struct {
    stack: Stack,
    locals: ArrayList(LocalEnvItem),
    envs: ArrayList(Env),
    string_table: ArrayList([]u8),
    builtin_table: ArrayList(Builtin),
};

// compilation unit
pub const Env_ = struct {
    name: []u8,
    table: AutoHashMap(usize, Value),
};

pub const Value_ = union(enum) {
    Int: i32,
    Float: f32,
    Boolean: bool,
    Symbol: usize,
    Builtin: usize,

    // Array: ArrayList(Value),
    // String: ArrayList(u8),
    Quotation: ArrayList(Literal),
    // Record: Record,

    Env: Env,
};

// parse ===
// symbols, strings, and words are interned into string_table
// builtins are interned into builtin_table

// interning is for speed of comparisons and less memory usage
//   so interning quotations isnt necessary

pub const Literal = union(enum) {
    Int: i32,
    Float: f32,
    Boolean: bool,
    Symbol: usize,
    String: usize,
    Word: usize,
    Builtin: usize,
    QuoteOpen,
    QuoteClose,
};

pub const ParseResult = struct {
    const Self = @This();

    literals: ArrayList(Literal),
    string_table: ArrayList([]const u8),
    builtin_table: ArrayList(Builtin),

    pub fn init(allocator: *Allocator) Self {
        return .{
            .literals = ArrayList(Literal).init(allocator),
            .string_table = ArrayList([]const u8).init(allocator),
            .builtin_table = ArrayList(Builtin).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.builtin_table.deinit();
        self.string_table.deinit();
        self.literals.deinit();
    }
};

// note: parser doesnt copy strings
pub const Parser = struct {
    const Self = @This();

    pub const Error = error{InvalidSymbol} || Allocator.Error;

    pub const ErrorInfo = struct {
        err: Error,
        line_num: usize,
    };

    error_info: ErrorInfo,

    pub fn init() Self {
        return .{
            .error_info = undefined,
        };
    }

    // TODO handle memory management in the event of errors
    // TODO different float parser
    // specialized parseInt that can parse hex like 0x0ff0
    pub fn parse(
        self: *Self,
        allocator: *Allocator,
        tokens: []const Token,
        builtins: []const Builtin,
    ) Error!ParseResult {
        var ret = ParseResult.init(allocator);

        for (tokens) |token| {
            switch (token.ty) {
                .String => {
                    var is_interned = false;
                    for (ret.string_table.items) |str, i| {
                        if (std.mem.eql(u8, token.str, str)) {
                            try ret.literals.append(.{ .String = i });
                            is_interned = true;
                        }
                    }
                    if (!is_interned) {
                        try ret.literals.append(.{ .String = ret.string_table.items.len });
                        try ret.string_table.append(token.str);
                    }
                },
                .Word => {
                    var try_parse_float =
                        !std.mem.eql(u8, token.str, "+") and
                        !std.mem.eql(u8, token.str, "-") and
                        !std.mem.eql(u8, token.str, ".");
                    const fl = std.fmt.parseFloat(f32, token.str) catch null;

                    var found_builtin: ?Builtin = null;
                    for (builtins) |bi| {
                        if (std.mem.eql(u8, token.str, bi.name)) {
                            found_builtin = bi;
                        }
                    }

                    if (token.str[0] == ':') {
                        if (token.str.len == 1) {
                            self.error_info = .{
                                .err = Error.InvalidSymbol,
                                .line_num = 0,
                            };
                            return self.error_info.err;
                        } else {
                            const name = token.str[1..];

                            var is_interned = false;
                            for (ret.string_table.items) |str, i| {
                                if (std.mem.eql(u8, name, str)) {
                                    try ret.literals.append(.{ .Symbol = i });
                                    is_interned = true;
                                }
                            }
                            if (!is_interned) {
                                try ret.literals.append(.{ .Symbol = ret.string_table.items.len });
                                try ret.string_table.append(token.str[1..]);
                            }
                        }
                    } else if (std.fmt.parseInt(i32, token.str, 10) catch null) |i| {
                        try ret.literals.append(.{ .Int = i });
                    } else if (try_parse_float and (fl != null)) {
                        try ret.literals.append(.{ .Float = fl.? });
                    } else if (std.mem.eql(u8, token.str, "#t")) {
                        try ret.literals.append(.{ .Boolean = true });
                    } else if (std.mem.eql(u8, token.str, "#f")) {
                        try ret.literals.append(.{ .Boolean = false });
                    } else if (std.mem.eql(u8, token.str, "{")) {
                        try ret.literals.append(.{ .QuoteOpen = {} });
                    } else if (std.mem.eql(u8, token.str, "}")) {
                        try ret.literals.append(.{ .QuoteClose = {} });
                    } else if (found_builtin != null) {
                        var is_interned = false;
                        for (ret.builtin_table.items) |bi, i| {
                            if (std.mem.eql(u8, token.str, bi.name)) {
                                try ret.literals.append(.{ .Builtin = i });
                                is_interned = true;
                            }
                        }
                        if (!is_interned) {
                            try ret.literals.append(.{ .Builtin = ret.builtin_table.items.len });
                            try ret.builtin_table.append(found_builtin.?);
                        }
                    } else {
                        var is_interned = false;
                        for (ret.string_table.items) |str, i| {
                            if (std.mem.eql(u8, token.str, str)) {
                                try ret.literals.append(.{ .Word = i });
                                is_interned = true;
                            }
                        }
                        if (!is_interned) {
                            try ret.literals.append(.{ .Word = ret.string_table.items.len });
                            try ret.string_table.append(token.str);
                        }
                    }
                },
            }
        }

        return ret;
    }
};

// evaluate ===

pub const Builtin = struct {
    name: []const u8,
    func: fn (ctx: *Context) Evaluator.Error!void,
};

pub const Record = struct {
    type_id: usize,
    slots: ArrayList(Value),
};

pub const RecordDef = struct {
    type_name: usize,
    slot_ct: usize,
};

// TODO userdata
pub const Value = union(enum) {
    Int: i32,
    Float: f32,
    Boolean: bool,
    Symbol: usize,
    Builtin: usize,

    // Array: ArrayList(Value),
    // String: ArrayList(u8),
    Quotation: ArrayList(Literal),
    Record: Record,

    // Env: Env,
};

pub const Stack = struct {
    const Self = @This();

    pub const Error = error{
        StackOverflow,
        StackUnderflow,
    } || Allocator.Error;

    data: ArrayList(Value),

    pub fn init(allocator: *Allocator) Self {
        return .{
            .data = ArrayList(Value).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // TODO free values
        self.data.deinit();
    }

    pub fn push(self: *Self, val: Value) Error!void {
        try self.data.append(val);
    }

    pub fn pop(self: *Self) Error!Value {
        if (self.data.items.len == 0) {
            return Error.StackUnderflow;
        }
        var ret = self.data.items[self.data.items.len - 1];
        self.data.items.len -= 1;
        return ret;
    }

    pub fn peek(self: *Self) Error!Value {
        var ret = self.data.items[self.data.items.len - 1];
        return ret;
    }
};

pub const Env = struct {
    const Self = @This();

    table: AutoHashMap(usize, Value),

    pub fn init(allocator: *Allocator) Self {
        return .{
            .table = AutoHashMap(usize, Value).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // TODO free values
        self.table.deinit();
    }

    pub fn insert(self: *Self, id: usize, val: Value) Allocator.Error!void {
        try self.table.put(id, val);
    }

    pub fn get(self: Self, id: usize) ?Value {
        return self.table.get(id);
    }
};

// TODO have a way to intern strings and builtins at runtime?
//        for adding more words or builtins from other files you need this
// TODO keep quotation_level in context?
pub const Context = struct {
    const Self = @This();

    string_table: [][]const u8,
    builtin_table: []Builtin,
    global_env: Env,
    stack: Stack,

    pub fn init(
        allocator: *Allocator,
        string_table: [][]const u8,
        builtin_table: []Builtin,
    ) Self {
        return .{
            .string_table = string_table,
            .builtin_table = builtin_table,
            .global_env = Env.init(allocator),
            .stack = Stack.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.stack.deinit();
        self.global_env.deinit();
    }

    // fn defineRecord() void{}
};

pub const Evaluator = struct {
    const Self = @This();

    pub const Error = error{
        WordNotFound,
        QuotationUnderflow,
        InternalError,
    } || Stack.Error || Allocator.Error;

    pub const ErrorInfo = struct {
        err: Error,
        line_num: usize,
    };

    error_info: ErrorInfo,

    pub fn init() Self {
        return .{
            .error_info = undefined,
        };
    }

    pub fn evaluate(
        self: *Self,
        allocator: *Allocator,
        literals: []const Literal,
        ctx: *Context,
    ) Error!void {
        var quotation_level: usize = 0;
        var quotation_buf = ArrayList(Literal).init(allocator);

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
                        return Error.QuotationUnderflow;
                    }
                    quotation_level -= 1;
                    if (quotation_level == 0) {
                        try ctx.stack.push(.{ .Quotation = quotation_buf });
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
                .Int => |i| try ctx.stack.push(Value{ .Int = i }),
                .Float => |f| try ctx.stack.push(Value{ .Float = f }),
                .Boolean => |b| try ctx.stack.push(Value{ .Boolean = b }),
                .Symbol => |idx| try ctx.stack.push(Value{ .Symbol = idx }),
                .String => |idx| {
                    // TODO
                },
                .Word => |idx| {
                    const val = ctx.global_env.get(idx);
                    if (val) |v| {
                        switch (v) {
                            .Quotation => |lits| {
                                // TODO handle quotation local envs
                                //   handle env stacks
                                try self.evaluate(allocator, lits.items, ctx);
                            },
                            .Builtin => |b_idx| {
                                try ctx.builtin_table[b_idx].func(ctx);
                            },
                            else => {
                                try ctx.stack.push(v);
                            },
                        }
                    } else {
                        return Error.WordNotFound;
                    }
                },
                .Builtin => |idx| {
                    try ctx.builtin_table[idx].func(ctx);
                },
                .QuoteOpen, .QuoteClose => {
                    std.log.info("really?", .{});
                    return Error.InternalError;
                },
            }
        }
    }
};
