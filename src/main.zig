const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;

//;

const lib = @import("lib.zig");
const builtins = @import("builtins.zig");

pub fn readFile(allocator: *Allocator, filename: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(filename, .{ .read = true });
    defer file.close();
    return file.readToEndAlloc(allocator, std.math.maxInt(usize));
}

pub fn main() !void {
    var alloc = std.heap.c_allocator;

    var f = try readFile(alloc, "tests/test.orth");

    const tokens = lib.tokenize(alloc, f) catch |err| {
        switch (err) {
            error.InvalidWord => {
                std.log.info("invalid word: {}", .{lib.error_info.line_number});
                return;
            },
            error.InvalidString => {
                std.log.info("invalid string: {}", .{lib.error_info.line_number});
                return;
            },
            else => return err,
        }
    };

    var vm = try lib.VM.init(alloc);

    const literals = try vm.parse(tokens.items);

    for (builtins.builtins) |bi| {
        const idx = try vm.internString(bi.name);
        try (try vm.envs.index(0)).insert(idx, .{
            .ForeignFnPtr = .{
                .name = idx,
                .func = bi.func,
            },
        });
    }

    const idx = try builtins.T.ft.internName(&vm);
    try (try vm.envs.index(0)).insertForeignType(
        idx,
        .{
            .name = idx,
            .equals_fn = builtins.T.equals,
        },
    );

    vm.eval(literals.items) catch |err| {
        switch (err) {
            error.WordNotFound => {
                std.log.info("word not found: {}", .{lib.error_info.word_not_found});
                return;
            },
            else => return err,
        }
    };
}
