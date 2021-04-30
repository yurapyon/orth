const std = @import("std");

const lib = @import("lib.zig");
usingnamespace lib;

//;

pub const Error = error{TypeError};

fn bi_define(ctx: *Context) Evaluator.Error!void {
    const name = try ctx.stack.pop();
    const value = try ctx.stack.pop();
    try ctx.global_env.insert(name.Symbol, value);
}

fn bi_define_record(ctx: *Context) Evaluator.Error!void {
    const name = try ctx.stack.pop();
    const quot = try ctx.stack.pop();
    for (quot.Quotation.items) |lit| {
        // TODO gotta define new words that arent interned yet
    }
    // try ctx.global_env.insert(name.Symbol, value);
}

fn bi_print_top(ctx: *Context) Evaluator.Error!void {
    std.log.info("TOP: {}", .{ctx.stack.peek()});
}

fn bi_print_stack(ctx: *Context) Evaluator.Error!void {
    std.log.info("STACK: len: {}", .{ctx.stack.data.items.len});
    for (ctx.stack.data.items) |it| {
        std.log.info("  {}", .{it});
    }
}

fn bi_add(ctx: *Context) Evaluator.Error!void {
    const b = try ctx.stack.pop();
    const a = try ctx.stack.pop();
    switch (b) {
        .Int => |bi| switch (a) {
            .Int => |ai| {
                try ctx.stack.push(.{ .Int = ai + bi });
            },
            .Float => |af| {
                try ctx.stack.push(.{ .Float = af + @intToFloat(f32, bi) });
            },
            else => {},
            // else => return Error.TypeError,
        },
        .Float => |bf| switch (a) {
            .Int => |ai| {
                try ctx.stack.push(.{ .Float = @intToFloat(f32, ai) + bf });
            },
            .Float => |af| {
                try ctx.stack.push(.{ .Float = af + bf });
            },
            else => {},
            // else => return Error.TypeError,
        },
        else => {},
        // else => return Error.TypeError,
    }
}

fn bi_sub(ctx: *Context) Evaluator.Error!void {
    const b = try ctx.stack.pop();
    const a = try ctx.stack.pop();
    switch (b) {
        .Int => |bi| switch (a) {
            .Int => |ai| {
                try ctx.stack.push(.{ .Int = ai - bi });
            },
            .Float => |af| {
                try ctx.stack.push(.{ .Float = af - @intToFloat(f32, bi) });
            },
            else => {},
            // else => return Error.TypeError,
        },
        .Float => |bf| switch (a) {
            .Int => |ai| {
                try ctx.stack.push(.{ .Float = @intToFloat(f32, ai) - bf });
            },
            .Float => |af| {
                try ctx.stack.push(.{ .Float = af - bf });
            },
            else => {},
            // else => return Error.TypeError,
        },
        else => {},
        // else => return Error.TypeError,
    }
}

pub const builtins = [_]Builtin{
    .{
        .name = "@",
        .func = bi_define,
    },
    .{
        .name = "@record",
        .func = bi_define_record,
    },
    .{
        .name = ".",
        .func = bi_print_top,
    },
    .{
        .name = ".stack",
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
};
