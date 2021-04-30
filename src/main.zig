const std = @import("std");
const StringHashMap = std.StringHashMap;

//;

const lib = @import("lib.zig");
const builtins = @import("builtins.zig").builtins;

pub fn main() !void {
    var alloc = std.heap.c_allocator;

    var tk = lib.Tokenizer.init();
    const tokens = tk.tokenize(alloc,
        \\ 10 :ten @
        \\ 10.0 :tenf @
        \\ { + } :plus @
        \\ ten .stack
        \\ ten ten plus .stack
        \\ ten tenf plus .stack
        \\ tenf ten plus .stack
        \\ tenf tenf plus .stack
    ) catch |err| switch (err) {
        error.InvalidWord => {
            std.log.info("invalid word: {}", .{tk.error_info.line_num});
            return;
        },
        error.InvalidString => {
            std.log.info("invalid string: {}", .{tk.error_info.line_num});
            return;
        },
        else => return err,
    };
    for (tokens.items) |tok, i| {
        // std.log.info("{} {} {}", .{ i, tok, tok.str.len });
    }

    var parser = lib.Parser.init();
    const parsed = try parser.parse(alloc, tokens.items, &builtins);

    for (parsed.literals.items) |lit| {
        std.log.info("{}", .{lit});
    }

    var eval = lib.Evaluator.init();
    var ctx = lib.Context.init(alloc, parsed.string_table.items, parsed.builtin_table.items);

    try eval.evaluate(alloc, parsed.literals.items, &ctx);

    tokens.deinit();
}
