const std = @import("std");
const tui = @import("tui");

pub fn copyToClipboard(allocator: std.mem.Allocator, data: []const u8, terminal: *tui.Terminal) !void {
    try terminal.disableRawMode();
    defer terminal.enableRawMode() catch {};

    const commands = .{
        &[_][]const u8{"wl-copy"},
        &[_][]const u8{ "xclip", "-selection", "clipboard" },
    };

    inline for (commands) |cmd| {
        var child = std.process.Child.init(cmd, allocator);
        child.stdin_behavior = .Pipe;
        child.stderr_behavior = .Ignore;

        if (child.spawn()) |_| {
            if (child.stdin) |stdin| {
                _ = stdin.writeAll(data) catch {};
                stdin.close();
                child.stdin = null;
            }
            _ = child.wait() catch {};
            return;
        } else |err| {
            if (err != error.FileNotFound) {
                return err;
            }
        }
    }

    // If we get here, no clipboard tool was found. Fail silently.
}
