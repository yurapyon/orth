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
    var vm = try VM.init(allocator);
    defer vm.deinit();

    try vm.defineWord("#t", .{ .Boolean = true });
    try vm.defineWord("#f", .{ .Boolean = false });
    try vm.defineWord("#sentinel", .{ .Sentinel = {} });

    for (builtins.builtins) |bi| {
        const idx = try vm.internSymbol(bi.name);
        vm.word_table.items[idx] = Value{
            .FFI_Fn = .{
                .name = idx,
                .func = bi.func,
            },
        };
    }

    // _ = try vm.installFFI_Type(&builtins.ft_quotation.ffi_type);
    // _ = try vm.installFFI_Type(&builtins.ft_vec.ffi_type);
    try builtins.ft_record.install(&vm);
    try builtins.ft_vec.install(&vm);
    try builtins.ft_map.install(&vm);

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

        while (try t.step()) {}
    }

    {
        var f = try readFile(allocator, "tests/test.orth");
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

        for (values) |val| {
            // t.nicePrintValue(val);
            // std.debug.print("\n", .{});
        }

        while (true) {
            var running = t.step() catch |err| {
                switch (err) {
                    error.WordNotFound => {
                        std.log.warn("word not found: {}", .{t.error_info.word_not_found});
                        // return err;
                        return;
                    },
                    else => {
                        std.log.warn("err: {}", .{err});
                        // return err;
                        return;
                    },
                }
            };
            if (!running) break;
        }
    }
}

test "main" {
    std.debug.print("\n", .{});
    try something(std.testing.allocator);
}

pub fn main() !void {
    try something(std.heap.c_allocator);
}
