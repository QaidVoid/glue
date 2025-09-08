pub const KeyBinding = struct {
    key: []const u8,
    description: []const u8,
};

pub const keymap = [_]KeyBinding{
    .{ .key = "↑/↓ or j/k", .description = "Navigate between stages" },
    .{ .key = "PgUp/PgDn", .description = "Scroll through stages" },
    .{ .key = "Enter or i", .description = "Enter data inspector mode" },
    .{ .key = "Tab", .description = "Switch between Input/Output in inspector" },
    .{ .key = "c", .description = "Copy inspector data to clipboard" },
    .{ .key = "r", .description = "Re-run pipeline from selected stage" },
    .{ .key = "R", .description = "Re-run entire pipeline" },
    .{ .key = "s", .description = "Save pipeline output to file" },
    .{ .key = "h or F1", .description = "Show/hide this help" },
    .{ .key = "Esc", .description = "Exit inspector/help mode" },
    .{ .key = "q or Ctrl+C", .description = "Quit application" },
    .{ .key = "Space", .description = "Pause/resume execution" },
};

const std = @import("std");
