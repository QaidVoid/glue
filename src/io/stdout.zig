pub const StdOut = struct {
    buf: [1024]u8 = undefined,
    file: std.fs.File,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .file = std.fs.File.stdout(),
        };
    }

    fn bufferedWriter(self: *Self) std.fs.File.Writer {
        return self.file.writer(&self.buf);
    }

    pub fn writeAll(self: *Self, bytes: []const u8) !void {
        var bw = self.bufferedWriter();
        try bw.interface.writeAll(bytes);
        try bw.interface.flush();
    }

    pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        var bw = self.file.writer(&self.buf);
        try bw.interface.print(fmt, args);
        try bw.interface.flush();
    }

    pub fn printLn(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        var bw = self.file.writer(&self.buf);
        try bw.interface.print(fmt ++ "\n", args);
        try bw.interface.flush();
    }
};

const std = @import("std");
