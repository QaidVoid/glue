const std = @import("std");
const app = @import("app");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: glue 'command1 | command2 | command3'\n", .{});
        std.debug.print("Example: glue 'ls -la | grep \\.txt | wc -l'\n", .{});
        return;
    }

    var app_instance = app.App.init(allocator) catch |err| {
        std.debug.print("Failed to initialize TUI: {}\n", .{err});
        std.debug.print("Your terminal might not support the required features.\n", .{});
        return;
    };
    defer app_instance.deinit();

    // Load and execute pipeline
    try app_instance.loadPipeline(args[1]);

    if (app_instance.pipeline.stages.items.len == 0) {
        std.debug.print("No valid stages found in pipeline: {s}\n", .{args[1]});
        return;
    }

    const execution_thread = try std.Thread.spawn(.{}, executePipelineAsync, .{&app_instance});
    defer execution_thread.join();

    // Start the interactive TUI
    try app_instance.run();
}

fn executePipelineAsync(app_ptr: *app.App) !void {
    try app_ptr.executePipeline(0);
}
