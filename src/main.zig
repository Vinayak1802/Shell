const std = @import("std");

// Define the function pointer type for command handlers
const FnType = *const fn (args_it: *std.mem.SplitIterator(u8, .sequence)) anyerror!void;

// Global hash map for storing built-in commands
var builtinHash: std.StringHashMap(FnType) = undefined;

pub fn main() !void {
    // Initialize the hash map with a page allocator
    builtinHash = std.StringHashMap(FnType).init(std.heap.page_allocator);
    defer builtinHash.deinit(); // Ensure resources are cleaned up

    // Register commands
    try builtinHash.put("echo", &echo);
    try builtinHash.put("exit", &exit);
    try builtinHash.put("type", &type_);

    // Main loop to handle user input
    while (true) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("$ ", .{});

        const stdin = std.io.getStdIn().reader();
        var buffer: [1024]u8 = undefined;
        const user_input = try stdin.readUntilDelimiter(&buffer, '\n');

        // Trim the trailing newline character from the input
        const trimmed_input = std.mem.trimRight(u8, user_input, "\n");

        // Split the trimmed input by spaces
        var it = std.mem.split(u8, trimmed_input, " ");
        const command = it.next() orelse "";

        if (command.len == 0) {
            continue;
        }

        // Look up the command in the hash map
        const builtin = builtinHash.get(command);
        if (builtin) |builtin_func| {
            try builtin_func(&it);
        } else {
            try stdout.print("{s}: command not found\n", .{command});
        }
    }
}

fn echo(args_it: *std.mem.SplitIterator(u8, .sequence)) anyerror!void {
    const stdout = std.io.getStdOut().writer();
    var is_first_arg = true;
    while (args_it.next()) |arg| {
        if (!is_first_arg) {
            try stdout.print(" ", .{});
        } else {
            is_first_arg = false;
        }
        try stdout.print("{s}", .{arg});
    }
    try stdout.print("\n", .{});
}

fn exit(args_it: *std.mem.SplitIterator(u8, .sequence)) anyerror!void {
    var status: u8 = 0;
    const status_arg = args_it.next() orelse "";
    status = std.fmt.parseInt(u8, status_arg, 10) catch @as(u8, 0);
    std.process.exit(status);
}
fn type_(args_it: *std.mem.SplitIterator(u8, .sequence)) anyerror!void {
    const stdout = std.io.getStdOut().writer();
    const arg = args_it.next() orelse "";
    if (arg.len == 0) {
        return;
    }

    // Check if the command is a shell builtin
    if (builtinHash.get(arg)) |builtin_func| {
        try stdout.print("{s} is a shell builtin\n", .{arg});
        return;
    }

    // Check if the command is an executable file in PATH
    const allocator = std.heap.page_allocator;
    const env_vars = try std.process.getEnvMap(allocator);
    const path_value = env_vars.get("PATH") orelse "";

    var path_it = std.mem.split(u8, path_value, ":");
    while (path_it.next()) |path| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, arg });
        defer allocator.free(full_path);

        const file = std.fs.openFileAbsolute(full_path, .{ .mode = .read_only }) catch {
            continue; // Skip if file cannot be opened
        };
        defer file.close();

        const file_info = try file.stat(); // Get file information
        const is_executable = file_info.mode & std.fs.FileMode.Executable != 0;
        if (is_executable) {
            try stdout.print("{s} is {s}\n", .{ arg, full_path });
            return;
        }
    }

    // If no match found
    try stdout.print("{s}: not found\n", .{arg});
}
