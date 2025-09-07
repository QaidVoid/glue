const std = @import("std");
const Terminal = @import("tui").Terminal;

pub const Color = enum {
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    bright_black,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,
    reset,

    pub fn ansiCode(self: Color, is_background: bool) []const u8 {
        if (is_background) {
            return switch (self) {
                .black => "\x1B[40m",
                .red => "\x1B[41m",
                .green => "\x1B[42m",
                .yellow => "\x1B[43m",
                .blue => "\x1B[44m",
                .magenta => "\x1B[45m",
                .cyan => "\x1B[46m",
                .white => "\x1B[47m",
                .bright_black => "\x1B[100m",
                .bright_red => "\x1B[101m",
                .bright_green => "\x1B[102m",
                .bright_yellow => "\x1B[103m",
                .bright_blue => "\x1B[104m",
                .bright_magenta => "\x1B[105m",
                .bright_cyan => "\x1B[106m",
                .bright_white => "\x1B[107m",
                .reset => "\x1B[0m", // Reset affects both
            };
        }

        return switch (self) {
            .black => "\x1B[30m",
            .red => "\x1B[31m",
            .green => "\x1B[32m",
            .yellow => "\x1B[33m",
            .blue => "\x1B[34m",
            .magenta => "\x1B[35m",
            .cyan => "\x1B[36m",
            .white => "\x1B[37m",
            .bright_black => "\x1B[90m",
            .bright_red => "\x1B[91m",
            .bright_green => "\x1B[92m",
            .bright_yellow => "\x1B[93m",
            .bright_blue => "\x1B[94m",
            .bright_magenta => "\x1B[95m",
            .bright_cyan => "\x1B[96m",
            .bright_white => "\x1B[97m",
            .reset => "\x1B[0m",
        };
    }
};

pub const Style = struct {
    fg: Color = .reset,
    bg: Color = .reset,
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    blink: bool = false,
    reverse: bool = false,

    pub fn apply(self: Style, terminal: *Terminal) !void {
        var buf: [64]u8 = undefined;
        var len: usize = 0;

        const reset = "\x1B[0m";
        @memcpy(buf[len .. len + reset.len], reset);
        len += reset.len;

        if (self.bold) {
            const bold_seq = "\x1B[1m";
            @memcpy(buf[len .. len + bold_seq.len], bold_seq);
            len += bold_seq.len;
        }

        if (self.dim) {
            const dim_seq = "\x1B[2m";
            @memcpy(buf[len .. len + dim_seq.len], dim_seq);
            len += dim_seq.len;
        }

        if (self.italic) {
            const italic_seq = "\x1B[3m";
            @memcpy(buf[len .. len + italic_seq.len], italic_seq);
            len += italic_seq.len;
        }

        if (self.underline) {
            const underline_seq = "\x1B[4m";
            @memcpy(buf[len .. len + underline_seq.len], underline_seq);
            len += underline_seq.len;
        }

        if (self.blink) {
            const blink_seq = "\x1B[5m";
            @memcpy(buf[len .. len + blink_seq.len], blink_seq);
            len += blink_seq.len;
        }

        if (self.reverse) {
            const reverse_seq = "\x1B[7m";
            @memcpy(buf[len .. len + reverse_seq.len], reverse_seq);
            len += reverse_seq.len;
        }

        const bg_code = self.bg.ansiCode(true);
        @memcpy(buf[len .. len + bg_code.len], bg_code);
        len += bg_code.len;

        const fg_code = self.fg.ansiCode(false);
        @memcpy(buf[len .. len + fg_code.len], fg_code);
        len += fg_code.len;

        try terminal.stdout.writeAll(buf[0..len]);
    }
};

pub const Rect = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,

    pub fn contains(self: Rect, x: u16, y: u16) bool {
        return x >= self.x and x < self.x + self.width and
            y >= self.y and y < self.y + self.height;
    }

    pub fn inner(self: Rect, margin: u16) Rect {
        const double_margin = margin * 2;
        return Rect{
            .x = self.x + margin,
            .y = self.y + margin,
            .width = if (self.width > double_margin) self.width - double_margin else 0,
            .height = if (self.height > double_margin) self.height - double_margin else 0,
        };
    }
};

pub const Widget = struct {
    rect: Rect,
    visible: bool = true,
    focused: bool = false,
};

pub const Border = enum {
    single,
    double,
    rounded,

    pub fn chars(self: Border) struct { top_left: []const u8, top_right: []const u8, bottom_left: []const u8, bottom_right: []const u8, horizontal: []const u8, vertical: []const u8 } {
        return switch (self) {
            .single => .{ .top_left = "┌", .top_right = "┐", .bottom_left = "└", .bottom_right = "┘", .horizontal = "─", .vertical = "│" },
            .double => .{ .top_left = "╔", .top_right = "╗", .bottom_left = "╚", .bottom_right = "╝", .horizontal = "═", .vertical = "║" },
            .rounded => .{ .top_left = "╭", .top_right = "╮", .bottom_left = "╰", .bottom_right = "╯", .horizontal = "─", .vertical = "│" },
        };
    }
};

pub fn drawBox(term: *Terminal, rect: Rect, title: ?[]const u8, style: Style, border_type: Border) !void {
    try style.apply(term);
    const chars = border_type.chars();

    // Top border
    try term.moveTo(rect.y, rect.x);
    if (title) |t| {
        var title_buf: [128]u8 = undefined;
        const formatted_title = try std.fmt.bufPrint(&title_buf, " {s} ", .{t});
        const title_len = formatted_title.len;
        const left_border_len = (rect.width - title_len) / 2;
        const right_border_len = rect.width - title_len - left_border_len;

        try term.stdout.writeAll(chars.top_left);
        for (0..left_border_len - 1) |_| try term.stdout.writeAll(chars.horizontal);
        try term.stdout.writeAll(formatted_title);
        for (0..right_border_len - 1) |_| try term.stdout.writeAll(chars.horizontal);
        try term.stdout.writeAll(chars.top_right);
    } else {
        try term.stdout.writeAll(chars.top_left);
        for (0..(rect.width - 2)) |_| try term.stdout.writeAll(chars.horizontal);
        try term.stdout.writeAll(chars.top_right);
    }

    // Middle borders
    for (1..rect.height - 1) |i| {
        try term.moveTo(rect.y + i, rect.x);
        try term.stdout.writeAll(chars.vertical);
        try term.moveTo(rect.y + i, rect.x + rect.width - 1);
        try term.stdout.writeAll(chars.vertical);
    }

    // Bottom border
    try term.moveTo(rect.y + rect.height - 1, rect.x);
    try term.stdout.writeAll(chars.bottom_left);
    for (0..(rect.width - 2)) |_| try term.stdout.writeAll(chars.horizontal);
    try term.stdout.writeAll(chars.bottom_right);

    try (Style{ .fg = .reset }).apply(term);
}
