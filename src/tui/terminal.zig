pub const Terminal = struct {
    original_termios: std.posix.termios,
    width: u16,
    height: u16,
    stdin: File,
    stdout: StdOut,

    const Self = @This();

    pub fn init() !Self {
        const stdin_fd = std.posix.STDIN_FILENO;
        const original = try std.posix.tcgetattr(stdin_fd);

        var terminal = Self{
            .original_termios = original,
            .width = 80,
            .height = 24,
            .stdin = File.stdin(),
            .stdout = StdOut.init(),
        };

        errdefer terminal.deinit();

        try terminal.enableRawMode();
        try terminal.enterAlternateScreen();
        try terminal.detectSize();
        try terminal.hideCursor();
        try terminal.enableMouse();

        return terminal;
    }

    pub fn deinit(self: *Self) void {
        self.showCursor() catch {};
        self.disableMouse() catch {};
        self.exitAlternateScreen() catch {};
        self.disableRawMode() catch {};
    }

    pub fn enableRawMode(self: *Self) !void {
        const stdin_fd = std.posix.STDIN_FILENO;
        var raw = self.original_termios;
        raw.iflag.ICRNL = false;
        raw.iflag.IXON = false;
        raw.oflag.OPOST = false;
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.ISIG = false;
        raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;
        raw.cc[@intFromEnum(std.posix.V.TIME)] = 1;
        try std.posix.tcsetattr(stdin_fd, .NOW, raw);
    }

    pub fn disableRawMode(self: *Self) !void {
        const stdin_fd = std.posix.STDIN_FILENO;
        try std.posix.tcsetattr(stdin_fd, .NOW, self.original_termios);
    }

    pub fn enableMouse(self: *Self) !void {
        try self.stdout.writeAll("\x1B[?1003h");
    }

    pub fn disableMouse(self: *Self) !void {
        try self.stdout.writeAll("\x1B[?1003l");
    }

    pub fn detectSize(self: *Self) !void {
        // Send cursor position report request
        try self.stdout.writeAll("\x1B[999;999H\x1B[6n");

        var response_buf: [32]u8 = undefined;
        var response_len: usize = 0;

        while (response_len < response_buf.len - 1) {
            const bytes_read = try self.stdin.read(response_buf[response_len .. response_len + 1]);
            if (bytes_read == 0) break;
            response_len += 1;
            if (response_buf[response_len - 1] == 'R') break;
        }

        if (response_len > 0) {
            const response = response_buf[0..response_len];
            if (std.mem.startsWith(u8, response, "\x1B[")) {
                var it = std.mem.tokenizeScalar(u8, response[2 .. response.len - 1], ';');
                if (it.next()) |row_str| {
                    if (it.next()) |col_str| {
                        self.height = std.fmt.parseInt(u16, row_str, 10) catch 24;
                        self.width = std.fmt.parseInt(u16, col_str, 10) catch 80;
                    }
                }
            }
        }

        if (self.width == 0 or self.height == 0) {
            self.width = 80;
            self.height = 24;
        }
    }

    pub fn enterAlternateScreen(self: *Self) !void {
        try self.stdout.writeAll("\x1B[?1049h");
    }

    pub fn exitAlternateScreen(self: *Self) !void {
        try self.stdout.writeAll("\x1B[?1049l");
    }

    pub fn hideCursor(self: *Self) !void {
        try self.stdout.writeAll("\x1B[?25l");
    }

    pub fn showCursor(self: *Self) !void {
        try self.stdout.writeAll("\x1B[?25h");
    }

    pub fn clearScreen(self: *Self) !void {
        try self.stdout.writeAll("\x1B[2J\x1B[H");
    }

    pub fn clearArea(self: *Self, start_row: u16, end_row: u16) !void {
        var row = start_row;
        while (row <= end_row) : (row += 1) {
            try self.clearLine(row);
        }
    }

    pub fn clearLine(self: *Self, row: u16) !void {
        try self.moveTo(row, 0);
        try self.stdout.writeAll("\x1B[K");
    }

    pub fn moveTo(self: *Self, row: u64, col: u64) !void {
        try self.stdout.print("\x1B[{};{}H", .{ row + 1, col + 1 });
    }

    pub fn readKey(self: *Self) !?u8 {
        var buffer: [1]u8 = undefined;
        const bytes_read = try self.stdin.read(&buffer);
        if (bytes_read == 0) return null;
        return buffer[0];
    }

    pub fn readSequence(self: *Self) ![]const u8 {
        var buffer: [16]u8 = undefined;
        var len: usize = 0;

        while (len < buffer.len) {
            const byte = self.readKey() catch break;
            if (byte == null) break;
            buffer[len] = byte.?;
            len += 1;

            // Break on common sequence endings
            if (byte.? == '~' or byte.? == 'R' or (len >= 3 and buffer[len - 1] >= 'A' and buffer[len - 1] <= 'Z')) {
                break;
            }
        }

        return buffer[0..len];
    }
};

const std = @import("std");
const File = std.fs.File;
const StdOut = @import("glue").StdOut;
