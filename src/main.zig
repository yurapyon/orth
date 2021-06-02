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

    try vm.installBaseLib();

    //;

    var f = try readFile(allocator, to_load orelse "tests/test.orth");
    defer allocator.free(f);

    var t = try vm.loadString(f);
    defer t.deinit();
    // t.enable_tco = false;

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
