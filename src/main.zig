const std = @import("std");
const Allocator = std.mem.Allocator;

//;

const lib = @import("lib.zig");
usingnamespace lib;
const builtins = @import("builtins.zig");

pub fn readFile(allocator: *Allocator, filename: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(filename, .{ .read = true });
    defer file.close();
    return file.readToEndAlloc(allocator, std.math.maxInt(usize));
}

pub fn something(allocator: *Allocator) !void {
    var to_load: ?[:0]u8 = null;
    var i: usize = 0;
    var args = std.process.args();
    while (args.next(allocator)) |arg_err| {
        const arg = try arg_err;
        if (i == 1) {
            to_load = arg;
        } else {
            allocator.free(arg);
        }
        i += 1;
    }

    var vm = try VM.init(allocator);
    defer vm.deinit();

    try vm.defineWord("#t", .{
        .value = .{ .Boolean = true },
        .eval_on_lookup = false,
    });
    try vm.defineWord("#f", .{
        .value = .{ .Boolean = false },
        .eval_on_lookup = false,
    });
    try vm.defineWord("#sentinel", .{
        .value = .{ .Sentinel = {} },
        .eval_on_lookup = false,
    });

    for (builtins.builtins) |bi| {
        const idx = try vm.internSymbol(bi.name);
        vm.word_table.items[idx] = .{
            .value = .{
                .FFI_Fn = .{
                    .name_id = idx,
                    .func = bi.func,
                },
            },
            .eval_on_lookup = true,
        };
    }

    try builtins.ft_record.install(&vm);
    try builtins.ft_vec.install(&vm);
    try builtins.ft_string.install(&vm);
    try builtins.ft_map.install(&vm);
    try builtins.ft_file.install(&vm);

    {
        var f = try readFile(allocator, "src/base.orth");
        defer allocator.free(f);

        var tk = Tokenizer.init(f);
        var tokens = std.ArrayList(Token).init(vm.allocator);
        defer tokens.deinit();

        while (try tk.next()) |tok| {
            try tokens.append(tok);
        }

        const values = try vm.parse(tokens.items);
        defer vm.allocator.free(values);

        var t = Thread.init(&vm, values);
        defer t.deinit();

        while (t.step() catch |err| {
            switch (err) {
                error.WordNotFound => {
                    std.log.warn("word not found: {}", .{t.error_info.word_not_found});
                    return err;
                },
                else => return err,
            }
        }) {}
    }

    if (to_load) |l| {
        var f = try readFile(allocator, l);
        defer allocator.free(f);

        var tk = Tokenizer.init(f);
        var tokens = std.ArrayList(Token).init(vm.allocator);
        defer tokens.deinit();

        while (try tk.next()) |tok| {
            try tokens.append(tok);
        }

        const values = try vm.parse(tokens.items);
        defer vm.allocator.free(values);

        var t = Thread.init(&vm, values);
        defer t.deinit();
        // t.enable_tco = false;

        for (values) |val| {
            // t.nicePrintValue(val);
            // std.debug.print("\n", .{});
        }

        while (true) {
            var running = t.step() catch |err| {
                switch (err) {
                    error.WordNotFound => {
                        std.log.warn("word not found: {}", .{t.error_info.word_not_found});
                        t.printStackTrace();
                        return;
                        // return err;
                    },
                    else => {
                        std.log.warn("err: {}", .{err});
                        t.printStackTrace();
                        // return;
                        return err;
                    },
                }
            };
            if (!running) break;
        }

        // std.debug.print("max stack: {}\n", .{t.stack.max});
        // std.debug.print("max ret stack: {}\n", .{t.return_stack.max});
        // std.debug.print("max res stack: {}\n", .{t.restore_stack.max});
    }

    if (to_load) |l| {
        allocator.free(l);
    }
}

test "main" {
    std.debug.print("\n", .{});
    try something(std.testing.allocator);
}

pub fn main() !void {
    try something(std.heap.c_allocator);
}
