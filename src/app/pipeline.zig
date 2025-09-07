const std = @import("std");
const core = @import("core");
const Stage = core.Stage;
const PipelineParser = core.PipelineParser;
const StageExecutor = core.StageExecutor;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const Pipeline = struct {
    allocator: Allocator,
    stages: ArrayList(Stage),
    parser: PipelineParser,
    executor: StageExecutor,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        return Self{
            .allocator = allocator,
            .stages = ArrayList(Stage).init(allocator),
            .parser = PipelineParser.init(allocator),
            .executor = StageExecutor.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.stages.items) |*stage| {
            stage.deinit(self.allocator);
        }
        self.stages.deinit();
        self.parser.deinit();
        self.executor.deinit();
    }

    pub fn load(self: *Self, pipeline_str: []const u8) !void {
        // The pipeline string is first parsed into a series of individual command strings.
        // Each of these commands will become a stage in the pipeline.
        const stage_commands = try self.parser.parseStages(pipeline_str);
        defer stage_commands.deinit();

        for (stage_commands.items) |cmd| {
            const stage = Stage.init(cmd);
            try self.stages.append(stage);
        }
    }
};
