const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

//;

// stack 0 is top

// once you parse something to values
//   you can get rid of the original text string
//   the vm deep copies strings
// values returned from parse
//   dont need to stay around for the life of the vm
//   the vm deep copies slices

// tokenizer syntax: " # : ;
//    parser syntax: { } float int
// i think thats all you need,
//   as in fancy 'defining syntax at runtime' like forth isnt neccessary

// error handling within orth is just result types
//   pass errors like type errors and div/0 errors to zig
//      with info about where it happened

//;

// envs/libraries are ways of naming units of code and controlling scope
//   all words are loaded into the word_table and converted to ids anyway
//   have ways to load new words into the vm from a hashtable
//     with renaming, excluding
//     define words into a hashtable linked to the current file youre loading
//       @env or something
//   vm word_table is the global lookup table for all words in the session

// unicode is currently not supported but i would like to have it in the future
//   shouldnt be hard
//     unicode chars
//     string_indent need to be updated

// rcs cant really be a built in type?
//   even though it would be nice to abstract some of the code out
//   if you make rcs built in that adds 3 more builtin types
//   doesnt stop you from needing finalizers, dupValue, thinking about moves
//     think it would get in the way

// TODO need
// tests
// error reporting
//   use error_info
//   stack trace thing
//   tokenize with col_num and line_num
//     parse with them too somehow?
// better number parsing
//   floats
//     ignore nan and inf
//   1234f 1234i
// use "//" for comments instead of ";" ?
// intern slices
// print contents of return stack
// get rid of sentinel type

// TODO want
// prevent invalid symbols
//   cant be parseable as numbers
//   cant start with #
//   symbols can't have spaces
//     what about string>symbol ?
// ffi threads
//   cooperative multithreading built into vm ?
//   modular scheduler thing not part of vm
//   yeild and resume
// parser
//   could do multiline strings like zig
//     would make the logic easier
//   multiline comments?
//     could use ( )
// records 100% in orth
//   weak ptrs for cyclic "record-type" record
//   auto generate doc strings
// u64 type ?
// dlsym ffi would be cool

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

    // TODO codepoints i.e. \x01, dont have \0
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
        IntEscape: i64,
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
        InvalidIntEscape,
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
        InCharEscape,
        InIntEscape,
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
                return ' ';
            } else if (std.mem.eql(u8, str, "tab")) {
                return '\t';
            } else if (std.mem.eql(u8, str, "newline")) {
                return '\n';
            } else {
                return error.InvalidCharEscape;
            }
        }
    }

    pub fn parseIntEscape(str: []const u8) Error!i64 {
        switch (str[0]) {
            'b' => return std.fmt.parseInt(i64, str[1..], 2) catch error.InvalidIntEscape,
            'x' => return std.fmt.parseInt(i64, str[1..], 16) catch error.InvalidIntEscape,
            else => return error.InvalidIntEscape,
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
                        // TODO check charIsWordValid
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
                    self.state = switch (ch) {
                        '\\' => .InCharEscape,
                        'x', 'b' => .InIntEscape,
                        // TODO
                        else => .InWord,
                    };
                },
                .InCharEscape => {
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
                .InIntEscape => {
                    if (charIsDelimiter(ch)) {
                        self.state = .Empty;
                        return Token{
                            .data = .{
                                .IntEscape = try parseIntEscape(
                                    self.buf[(self.start_char + 1)..(self.end_char - 1)],
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
                .InCharEscape => {
                    self.state = .Empty;
                    return Token{
                        .data = .{
                            .CharEscape = try parseCharEscape(
                                self.buf[(self.start_char + 2)..self.end_char],
                            ),
                        },
                    };
                },
                .InIntEscape => {
                    self.state = .Empty;
                    return Token{
                        .data = .{
                            .IntEscape = try parseIntEscape(
                                self.buf[(self.start_char + 1)..(self.end_char - 1)],
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
    Slice: []const Value,
    FFI_Fn: FFI_Fn,
    FFI_Ptr: FFI_Ptr,
};

pub const ValueType = @TagType(Value);

//;

pub const RecordType = struct {
    // TODO keep slot names
    slot_ct: usize,
    // display_fn: Value,
    // equivalent_fn: Value,
};

pub const FFI_Type = struct {
    display_fn: fn (*Thread, FFI_Ptr) void = defaultDisplay,
    equivalent_fn: fn (*Thread, FFI_Ptr, Value) bool = defaultEquivalent,
    // TODO can this throw errors
    dup_fn: fn (*VM, FFI_Ptr) FFI_Ptr = defaultDup,
    drop_fn: fn (*VM, FFI_Ptr) void = defaultDrop,

    fn defaultDisplay(t: *Thread, ptr: FFI_Ptr) void {
        const name_id = t.vm.type_table.items[ptr.type_id].name_id;
        std.debug.print("*<{} {}>", .{
            t.vm.symbol_table.items[name_id],
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
};

pub const OrthType = struct {
    pub const Type = union(enum) {
        Primitive,
        Record: RecordType,
        FFI: FFI_Type,
    };

    ty: Type,
    name_id: usize = undefined,
};

//;

pub const ReturnValue = struct {
    value: Value,
    restore_ct: usize,
};

pub const DefinedWord = struct {
    value: Value,
    eval_on_lookup: bool,
};

pub const VM = struct {
    const Self = @This();

    pub const ErrorInfo = struct {
        word_not_found: []const u8,
    };

    allocator: *Allocator,
    error_info: ErrorInfo,

    symbol_table: ArrayList([]const u8),
    word_table: ArrayList(?DefinedWord),
    type_table: ArrayList(OrthType),

    string_literals: ArrayList([]const u8),
    // note: this coud be a Stack([]const Value)
    //   but there is a zig bug
    //   just going to use a Value that will always be a Value.Slice
    slice_literals: ArrayList(Value),

    pub fn init(allocator: *Allocator) Allocator.Error!Self {
        var ret = Self{
            .allocator = allocator,
            .error_info = undefined,

            .symbol_table = ArrayList([]const u8).init(allocator),
            .word_table = ArrayList(?DefinedWord).init(allocator),
            .type_table = ArrayList(OrthType).init(allocator),

            .string_literals = ArrayList([]const u8).init(allocator),
            .slice_literals = ArrayList(Value).init(allocator),
        };
        const PrimitiveTypeData = struct {
            id: ValueType,
            name: []const u8,
        };
        const primitive_types = [_]PrimitiveTypeData{
            .{ .id = .Int, .name = "int" },
            .{ .id = .Float, .name = "float" },
            .{ .id = .Char, .name = "char" },
            .{ .id = .Boolean, .name = "boolean" },
            .{ .id = .Sentinel, .name = "sentinel" },
            .{ .id = .String, .name = "string-literal" },
            .{ .id = .Word, .name = "word" },
            .{ .id = .Symbol, .name = "symbol" },
            .{ .id = .Slice, .name = "slice" },
            .{ .id = .FFI_Fn, .name = "ffi-fn" },
            .{ .id = .FFI_Ptr, .name = "ffi-ptr" },
        };
        for (primitive_types) |p| {
            std.debug.assert(@enumToInt(p.id) ==
                try ret.installType(
                p.name,
                .{ .ty = .{ .Primitive = {} } },
            ));
        }
        return ret;
    }

    pub fn deinit(self: *Self) void {
        for (self.word_table.items) |dword| {
            if (dword) |w| {
                self.dropValue(w.value);
            }
        }

        for (self.slice_literals.items) |val| {
            for (val.Slice) |v| {
                self.dropValue(v);
            }
        }

        for (self.slice_literals.items) |val| {
            self.allocator.free(val.Slice);
        }
        self.slice_literals.deinit();
        for (self.string_literals.items) |str| {
            self.allocator.free(str);
        }
        self.string_literals.deinit();
        self.type_table.deinit();
        self.word_table.deinit();
        for (self.symbol_table.items) |sym| {
            self.allocator.free(sym);
        }
        self.symbol_table.deinit();
    }

    // parse ===

    // TODO make a version of this that doesnt duplicate the string
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

    // TODO handle memory if theres an error
    //   possible errors are allocator errors and slice errors
    pub fn parse(self: *Self, tokens: []const Token) Allocator.Error![]Value {
        var ret = ArrayList(Value).init(self.allocator);

        var slice_stack = Stack(ArrayList(Value)).init(self.allocator);
        defer slice_stack.deinit();

        for (tokens) |token| {
            const append_to: *ArrayList(Value) = if (slice_stack.data.items.len > 0) blk: {
                break :blk slice_stack.index(0) catch unreachable;
            } else &ret;

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

                    try append_to.append(.{ .String = buf });
                },
                .CharEscape => |ch| {
                    try append_to.append(.{ .Char = ch });
                },
                .IntEscape => |i| {
                    try append_to.append(.{ .Int = i });
                },
                .Symbol => |sym| {
                    try append_to.append(.{ .Symbol = try self.internSymbol(sym) });
                },
                .Word => |word| {
                    if (std.mem.eql(u8, word, "{")) {
                        try slice_stack.push(ArrayList(Value).init(self.allocator));
                    } else if (std.mem.eql(u8, word, "}")) {
                        // TODO handle this error for stack underflow
                        var slice_arraylist = slice_stack.pop() catch unreachable;
                        const slice = .{ .Slice = slice_arraylist.toOwnedSlice() };
                        try self.slice_literals.append(slice);
                        if (slice_stack.data.items.len > 0) {
                            try (slice_stack.index(0) catch unreachable).append(slice);
                        } else {
                            try ret.append(slice);
                        }
                    } else {
                        const try_parse_float =
                            !std.mem.eql(u8, word, "+") and
                            !std.mem.eql(u8, word, "-") and
                            !std.mem.eql(u8, word, ".");
                        const fl = std.fmt.parseFloat(f32, word) catch null;

                        if (std.fmt.parseInt(i32, word, 10) catch null) |i| {
                            try append_to.append(.{ .Int = i });
                        } else if (try_parse_float and (fl != null)) {
                            try append_to.append(.{ .Float = fl.? });
                        } else {
                            try append_to.append(.{ .Word = try self.internSymbol(word) });
                        }
                    }
                },
            }
        }

        // TODO if qstack still has stuff on it thats an error

        return ret.toOwnedSlice();
    }

    // eval ===

    pub fn dupValue(self: *Self, val: Value) Value {
        switch (val) {
            .FFI_Ptr => |ptr| return .{
                .FFI_Ptr = self.type_table.items[ptr.type_id].ty.FFI.dup_fn(self, ptr),
            },
            else => return val,
        }
    }

    pub fn dropValue(self: *Self, val: Value) void {
        if (val == .FFI_Ptr) {
            const ptr = val.FFI_Ptr;
            self.type_table.items[ptr.type_id].ty.FFI.drop_fn(self, ptr);
        }
    }

    //;

    // returns type id
    pub fn installType(self: *Self, name: []const u8, ty: OrthType) Allocator.Error!usize {
        const idx = self.type_table.items.len;
        try self.type_table.append(ty);
        self.type_table.items[idx].name_id = try self.internSymbol(name);
        return idx;
    }

    // TODO dupValue here?
    //   this is designed to be used from within zig not in ffi_fns
    pub fn defineWord(self: *Self, name: []const u8, dword: DefinedWord) Allocator.Error!void {
        const idx = try self.internSymbol(name);
        self.word_table.items[idx] = dword;
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
    restore_ct: usize,

    stack: Stack(Value),
    return_stack: Stack(ReturnValue),
    restore_stack: Stack(Value),

    pub fn init(vm: *VM, values: []const Value) Self {
        var ret = .{
            .vm = vm,
            .error_info = undefined,

            .current_execution = values,
            .restore_ct = 0,

            .stack = Stack(Value).init(vm.allocator),
            .return_stack = Stack(ReturnValue).init(vm.allocator),
            .restore_stack = Stack(Value).init(vm.allocator),
        };
        return ret;
    }

    pub fn deinit(self: *Self) void {
        for (self.restore_stack.data.items) |val| {
            self.vm.dropValue(val);
        }
        for (self.stack.data.items) |val| {
            self.vm.dropValue(val);
        }
        self.restore_stack.deinit();
        self.return_stack.deinit();
        self.stack.deinit();
    }

    //;

    // TODO would be nice if i could move this into vm
    //  but FFI_Ptr.display_fn needs *Thread
    pub fn nicePrintValue(self: *Self, value: Value) void {
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
            .Symbol => |val| std.debug.print(":{}", .{self.vm.symbol_table.items[val]}),
            .Word => |val| std.debug.print("\\{}", .{self.vm.symbol_table.items[val]}),
            .String => |val| std.debug.print("\"{}\"L", .{val}),
            .Slice => |slc| {
                std.debug.print("{{ ", .{});
                for (slc) |val| {
                    self.nicePrintValue(val);
                    std.debug.print(" ", .{});
                }
                std.debug.print("}}L", .{});
            },
            .FFI_Fn => |val| std.debug.print("fn({})", .{self.vm.symbol_table.items[val.name]}),
            .FFI_Ptr => |ptr| self.vm.type_table.items[ptr.type_id].ty.FFI.display_fn(self, ptr),
        }
    }

    //;

    // NOTE: just moves value, does not dup it
    pub fn evaluateValue(self: *Self, value: Value, restore_ct: usize) Error!void {
        switch (value) {
            .Word => |idx| {
                const found_word = self.vm.word_table.items[idx];
                if (found_word) |dword| {
                    if (dword.eval_on_lookup) {
                        // found_word can't be a word or this may loop
                        //TODO make a different error for this
                        if (dword.value == .Word) return error.InternalError;
                        try self.evaluateValue(self.vm.dupValue(dword.value), 0);
                    } else {
                        try self.stack.push(self.vm.dupValue(dword.value));
                    }
                } else {
                    self.error_info.word_not_found = self.vm.symbol_table.items[idx];
                    return error.WordNotFound;
                }
            },
            .Slice => |slc| {
                if (!(self.current_execution.len == 0 and self.restore_ct == 0)) {
                    try self.return_stack.push(.{
                        .value = .{ .Slice = self.current_execution },
                        .restore_ct = self.restore_ct,
                    });
                }
                self.current_execution = slc;
                self.restore_ct = restore_ct;
            },
            .FFI_Fn => |fp| try fp.func(self),
            else => try self.stack.push(value),
        }
    }

    pub fn readValue(self: *Self, value: Value) Error!void {
        switch (value) {
            .Word => |idx| try self.evaluateValue(value, 0),
            else => |val| try self.stack.push(val),
        }
    }

    pub fn step(self: *Self) Error!bool {
        while (self.current_execution.len != 0) {
            var value = self.current_execution[0];
            self.current_execution.ptr += 1;
            self.current_execution.len -= 1;
            // TODO handle thread errors here, any errors besides allocator errors
            //  readValue() shouldnt handle errors as `read` from within orth might do something different with them
            try self.readValue(value);
            return true;
        }

        var i: usize = 0;
        while (i < self.restore_ct) : (i += 1) {
            try self.stack.push(try self.restore_stack.pop());
        }

        if (self.return_stack.data.items.len > 0) {
            const rv = self.return_stack.pop() catch unreachable;
            if (rv.restore_ct == std.math.maxInt(usize)) {
                // TODO this can happen with invalid restore count
                //   or a word leaving things on the return stack
                return error.InvalidReturnValue;
            }

            // TODO checking current_execution len here could be used for tco
            self.current_execution = rv.value.Slice;
            self.restore_ct = rv.restore_ct;
            return true;
        } else {
            return false;
        }
    }
};
