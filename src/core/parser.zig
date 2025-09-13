pub const PipelineParser = struct {
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn parseStages(self: *Self, pipeline: []const u8) !ArrayList([]const u8) {
        var stages: ArrayList([]const u8) = .empty;

        var i: usize = 0;
        var stage_start: usize = 0;
        var in_single_quote = false;
        var in_double_quote = false;
        var escaped = false;
        var paren_level: usize = 0;

        while (i < pipeline.len) {
            const char = pipeline[i];

            if (escaped) {
                escaped = false;
                i += 1;
                continue;
            }

            switch (char) {
                '\\' => {
                    // Handle escape sequences. This is important for ensuring that special characters
                    // within quotes or other contexts are treated as literals rather than symbols
                    // with special meaning (e.g., a quote inside a quoted string).
                    escaped = true;
                },
                '\'' => {
                    // Single quotes are toggled only when not inside double quotes. This prevents
                    // a single quote from being misinterpreted as the end of a string if it's
                    // part of a double-quoted string.
                    if (!in_double_quote) {
                        in_single_quote = !in_single_quote;
                    }
                },
                '"' => {
                    // Double quotes are toggled only when not inside single quotes for the same
                    // reason as single quotes—to avoid premature termination of a string.
                    if (!in_single_quote) {
                        in_double_quote = !in_double_quote;
                    }
                },
                '(' => {
                    paren_level += 1;
                },
                ')' => {
                    if (paren_level > 0) {
                        paren_level -= 1;
                    }
                },
                '|' => {
                    // A pipe is treated as a stage separator only if it's not inside quotes or
                    // parentheses. This allows pipes to be used as literal characters within
                    // command arguments when properly quoted or grouped.
                    if (!in_single_quote and !in_double_quote and paren_level == 0) {
                        // Found a pipe separator
                        const stage = std.mem.trim(u8, pipeline[stage_start..i], " \t\n\\");
                        if (stage.len > 0) {
                            const stage_copy = try self.allocator.dupe(u8, stage);
                            try stages.append(self.allocator, stage_copy);
                        }
                        stage_start = i + 1;
                    }
                },
                else => {},
            }

            i += 1;
        }

        // The final part of the pipeline string is treated as the last stage. This ensures
        // that any command sequence not ending with a pipe is still processed correctly.
        const final_stage = std.mem.trim(u8, pipeline[stage_start..], " \t\n\\");
        if (final_stage.len > 0) {
            const stage_copy = try self.allocator.dupe(u8, final_stage);
            try stages.append(self.allocator, stage_copy);
        }

        return stages;
    }
};

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
