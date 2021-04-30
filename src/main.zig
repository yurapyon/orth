const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;

//;

const lib = @import("lib.zig");
const builtins = @import("builtins.zig").builtins;

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
                std.log.info("invalid word: {}", .{lib.error_info.lineNumber()});
                return;
            },
            error.InvalidString => {
                std.log.info("invalid string: {}", .{lib.error_info.lineNumber()});
                return;
            },
            else => return err,
        }
    };

    var vm = try lib.VM.init(alloc);

    const literals = try vm.parse(tokens.items);

    for (builtins) |bi| {
        try vm.envs.data.items[0].insert(try vm.internString(bi.name), .{
            .ForeignFn = bi.func,
        });
    }

    try vm.eval(literals.items);
}
