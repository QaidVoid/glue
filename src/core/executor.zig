pub const StageExecutor = struct {
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn executeStage(self: *Self, stage: *Stage, input: []const u8) !void {
        stage.status = .running;
        const start_time = std.time.milliTimestamp();

        var child = std.process.Child.init(&[_][]const u8{ "sh", "-c", stage.command }, self.allocator);
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        // The input from the previous stage (or the initial input) is written to the
        // standard input of the child process. This is how data is piped from one
        // stage to the next. After writing, the stdin is closed to signal the end of input.
        if (child.stdin) |stdin| {
            _ = try stdin.writeAll(input);
            stdin.close();
            child.stdin = null;
        }

        var output: ArrayList(u8) = .empty;
        defer output.deinit(self.allocator);

        var error_output: ArrayList(u8) = .empty;
        defer error_output.deinit(self.allocator);

        // The standard output of the child process is read in a loop until no more
        // data is available. This captured output becomes the input for the next stage
        // in the pipeline. A buffer is used to read the output in chunks.
        if (child.stdout) |stdout| {
            var internal_buf: [4096]u8 = undefined;
            var reader = stdout.reader(&internal_buf);
            reader.mode = .streaming;

            var read_buffer: [4096]u8 = undefined;
            while (true) {
                const bytes_read = reader.read(&read_buffer) catch 0;
                if (bytes_read == 0) break;
                try output.appendSlice(self.allocator, read_buffer[0..bytes_read]);
            }

            stdout.close();
            child.stdout = null;
        }

        if (child.stderr) |stderr| {
            var buffer: [4096]u8 = undefined;
            var reader = stderr.reader(&buffer);
            reader.mode = .streaming;

            var read_buffer: [4096]u8 = undefined;
            while (true) {
                const bytes_read = reader.read(&read_buffer) catch 0;
                if (bytes_read == 0) break;
                try error_output.appendSlice(self.allocator, read_buffer[0..bytes_read]);
            }
            stderr.close();
            child.stderr = null;
        }

        const term = try child.wait();
        const end_time = std.time.milliTimestamp();

        stage.input_data = try self.allocator.dupe(u8, input);
        stage.output_data = try output.toOwnedSlice(self.allocator);
        stage.execution_time = @intCast(end_time - start_time);
        stage.data_size = stage.output_data.len;

        if (term != .Exited or term.Exited != 0) {
            stage.status = .@"error";
            if (error_output.items.len > 0) {
                stage.error_msg = try error_output.toOwnedSlice(self.allocator);
            } else {
                stage.error_msg = try self.allocator.dupe(u8, "Command failed");
            }
        } else {
            stage.status = .completed;
        }
    }
};

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Stage = @import("glue").Stage;
