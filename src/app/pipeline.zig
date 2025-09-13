pub const Pipeline = struct {
    allocator: Allocator,
    stages: ArrayList(Stage) = .empty,
    parser: PipelineParser,
    executor: StageExecutor,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        return Self{
            .allocator = allocator,
            .parser = PipelineParser.init(allocator),
            .executor = StageExecutor.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.stages.items) |*stage| {
            stage.deinit(self.allocator);
        }
        self.stages.deinit(self.allocator);
        self.parser.deinit();
        self.executor.deinit();
    }

    pub fn load(self: *Self, pipeline_str: []const u8) !void {
        // The pipeline string is first parsed into a series of individual command strings.
        // Each of these commands will become a stage in the pipeline.
        var stage_commands = try self.parser.parseStages(pipeline_str);
        defer stage_commands.deinit(self.allocator);

        for (stage_commands.items) |cmd| {
            const stage = Stage.init(cmd);
            try self.stages.append(self.allocator, stage);
        }
    }
};

const std = @import("std");
const glue = @import("glue");
const Stage = glue.Stage;
const PipelineParser = glue.PipelineParser;
const StageExecutor = glue.StageExecutor;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
