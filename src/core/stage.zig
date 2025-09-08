pub const Stage = struct {
    command: []const u8,
    input_data: []u8,
    output_data: []u8,
    execution_time: u64 = 0,
    data_size: usize = 0,
    error_msg: ?[]const u8,
    status: enum { pending, running, completed, @"error" } = .pending,

    const Self = @This();

    pub fn init(cmd: []const u8) Self {
        return Self{
            .command = cmd,
            .input_data = &[_]u8{},
            .output_data = &[_]u8{},
            .error_msg = null,
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.command);
        if (self.input_data.len > 0) allocator.free(self.input_data);
        if (self.output_data.len > 0) allocator.free(self.output_data);
        if (self.error_msg) |err| allocator.free(err);
    }
};

const std = @import("std");
const Allocator = std.mem.Allocator;
