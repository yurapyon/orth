const std = @import("std");
const Allocator = std.mem.Allocator;

//;

const lib = @import("lib.zig");
const builtins = @import("builtins.zig");

pub fn readFile(allocator: *Allocator, filename: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(filename, .{ .read = true });
    defer file.close();
    return file.readToEndAlloc(allocator, std.math.maxInt(usize));
}

pub fn something(allocator: *Allocator) !void {
    var vm = lib.VM.init(allocator);
    defer vm.deinit();

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

    _ = try vm.installFFI_Type(&builtins.ft_vec.ffi_type);
    // _ = try vm.installFFI_Type(builtins.ft_proto.ft);

    var base_f = try readFile(allocator, "src/base.orth");
    defer allocator.free(base_f);

    const base_vals = try vm.parse(base_f);
    defer base_vals.deinit();

    try vm.eval(base_vals.items);

    //;

    var f = try readFile(allocator, "tests/test.orth");
    defer allocator.free(f);

    const test_vals = vm.parse(f) catch |err| {
        switch (err) {
            error.InvalidWord => {
                std.log.warn("invalid word: {}", .{vm.error_info.line_number});
                return;
            },
            error.InvalidString => {
                std.log.warn("invalid string: {}", .{vm.error_info.line_number});
                return;
            },
            else => return err,
        }
    };
    defer test_vals.deinit();

    vm.eval(test_vals.items) catch |err| {
        switch (err) {
            error.WordNotFound => {
                std.log.warn("word not found: {}", .{vm.error_info.word_not_found});
                return;
            },
            else => {
                std.log.warn("err: {}", .{err});
                return err;
            },
        }
    };
}

test "main" {
    std.debug.print("\n", .{});
    try something(std.testing.allocator);
}

pub fn main() !void {
    try something(std.heap.c_allocator);
}
