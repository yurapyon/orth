const std = @import("std");
const StringHashMap = std.StringHashMap;

const lib = @import("lib.zig");

//;

fn bi_print_stack(ctx: *lib.Context) lib.Evaluator.Error!void {
    std.log.info("STACK:", .{});
    for (ctx.stack.data.items) |it| {
        std.log.info("  {}", .{it});
    }
}

fn bi_add(ctx: *lib.Context) lib.Evaluator.Error!void {
    const b = try ctx.stack.pop();
    const a = try ctx.stack.pop();
    try ctx.stack.push(.{ .Int = a.Int + b.Int });
}

fn bi_sub(ctx: *lib.Context) lib.Evaluator.Error!void {
    const b = try ctx.stack.pop();
    const a = try ctx.stack.pop();
    try ctx.stack.push(.{ .Int = a.Int - b.Int });
}

fn bi_define(ctx: *lib.Context) lib.Evaluator.Error!void {
    const name = try ctx.stack.pop();
    const value = try ctx.stack.pop();
    try ctx.global_env.insert(name.Symbol, value);
}

pub fn main() !void {
    var alloc = std.heap.c_allocator;

    var tk = lib.Tokenizer.init();
    const tokens = tk.tokenize(alloc,
        \\ 10 :ten @
        \\ { + } :plus @
        \\ ten .
        \\ ten ten plus .
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

    var builtins = [_]lib.Builtin{
        .{
            .name = ".",
            .func = bi_print_stack,
        },
        .{
            .name = "+",
            .func = bi_add,
        },
        .{
            .name = "-",
            .func = bi_sub,
        },
        .{
            .name = "@",
            .func = bi_define,
        },
    };

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
