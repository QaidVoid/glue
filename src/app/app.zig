const PipelineContext = struct {
    app: *App,
    start_stage: usize,
};

pub const App = struct {
    allocator: Allocator,
    terminal: tui.Terminal,
    pipeline: Pipeline,
    selected_stage: usize = 0,
    last_selected_stage: usize = 0,
    view_mode: enum { overview, inspector, help } = .overview,
    scroll_offset: usize = 0,
    inspector_view: enum { input, output } = .output,
    inspector_scroll: usize = 0,
    quit_requested: bool = false,
    needs_redraw: bool = true,
    needs_full_render: bool = true,
    last_render_hash: u64 = 0,
    stages_to_rerender: ArrayList(usize),
    app_mutex: Mutex = .{},
    animation_tick: u8 = 0,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        return Self{
            .allocator = allocator,
            .terminal = try tui.Terminal.init(),
            .pipeline = try Pipeline.init(allocator),
            .stages_to_rerender = ArrayList(usize).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.pipeline.deinit();
        self.stages_to_rerender.deinit();
        self.terminal.deinit();
    }

    pub fn loadPipeline(self: *Self, pipeline_str: []const u8) !void {
        try self.pipeline.load(pipeline_str);
        self.needs_full_render = true;
        self.needs_redraw = true;
    }

    pub fn run(self: *Self) !void {
        while (!self.quit_requested) {
            if (self.needs_redraw) {
                try tui.view.render(self);
                self.needs_redraw = false;
            }

            const input_handled = try self.handleInput();

            if (!input_handled and !self.needs_redraw) {
                std.time.sleep(50_000_000);
            }

            if (self.hasRunningStages()) {
                std.time.sleep(50_000_000);
                try tui.view.render(self);
            }

            self.animation_tick +%= 1;
        }
    }

    fn setScrollOffset(self: *Self, offset: usize) bool {
        if (offset == self.scroll_offset) return false;

        self.scroll_offset = offset;
        return true;
    }

    fn setInspectorScroll(self: *Self, scroll: usize) bool {
        if (scroll == self.inspector_scroll) return false;

        self.inspector_scroll = scroll;
        self.needs_redraw = true;
        return true;
    }

    fn handleInput(self: *Self) !bool {
        const key_event = tui.parseKeyEvent(&self.terminal) catch return false;
        if (key_event == .unknown) return false;

        switch (self.view_mode) {
            .overview => try self.handleOverviewInput(key_event),
            .inspector => try self.handleInspectorInput(key_event),
            .help => try self.handleHelpInput(key_event),
        }
        return true;
    }

    fn handleOverviewInput(self: *Self, key: tui.KeyEvent) !void {
        switch (key) {
            .char => |ch| switch (ch) {
                'q', 'Q' => self.quit_requested = true,
                'h', 'H', '?' => {
                    self.view_mode = .help;
                    self.needs_redraw = true;
                },
                'i', 'I' => {
                    self.view_mode = .inspector;
                    self.needs_redraw = true;
                },
                'j', 'J' => {
                    self.moveDown();
                    self.needs_redraw = true;
                },
                'k', 'K' => {
                    self.moveUp();
                    self.needs_redraw = true;
                },
                'r' => try self.rerunFromStage(),
                'R' => try self.rerunPipeline(),
                's', 'S' => try self.saveOutput(),
                ' ' => try self.togglePause(),
                else => {},
            },

            .arrow_up => {
                self.moveUp();
                self.needs_redraw = true;
            },
            .arrow_down => {
                self.moveDown();
                self.needs_redraw = true;
            },
            .page_up => {
                self.pageUp();
                self.needs_redraw = true;
            },
            .page_down => {
                self.pageDown();
                self.needs_redraw = true;
            },
            .home => {
                self.selected_stage = 0;
                self.adjustScrollForSelection();
                self.needs_redraw = true;
            },
            .end => {
                if (self.pipeline.stages.items.len > 0) {
                    self.selected_stage = self.pipeline.stages.items.len - 1;
                    self.adjustScrollForSelection();
                    self.needs_redraw = true;
                }
            },
            .enter => {
                self.view_mode = .inspector;
                self.needs_redraw = true;
            },
            .f1 => {
                self.view_mode = .help;
                self.needs_redraw = true;
            },
            .mouse => |mouse_event| {
                // Ignore mouse events
                _ = mouse_event;
            },
            else => {},
        }
    }

    fn handleInspectorInput(self: *Self, key: tui.KeyEvent) !void {
        switch (key) {
            .char => |ch| switch (ch) {
                'q', 'Q' => self.quit_requested = true,
                'j', 'J' => {
                    self.inspectorScrollDown();
                    self.needs_redraw = true;
                },
                'k', 'K' => {
                    self.inspectorScrollUp();
                    self.needs_redraw = true;
                },
                'c', 'C' => {
                    const stage = &self.pipeline.stages.items[self.selected_stage];
                    const data = switch (self.inspector_view) {
                        .input => stage.input_data,
                        .output => if (stage.status == .@"error") stage.error_msg.? else stage.output_data,
                    };
                    tui.utils.copyToClipboard(self.allocator, data, &self.terminal) catch {};
                },
                else => {},
            },
            .tab => {
                self.inspector_view = switch (self.inspector_view) {
                    .input => .output,
                    .output => .input,
                };
                self.inspector_scroll = 0;
                self.needs_redraw = true;
            },
            .arrow_up => self.inspectorScrollUp(),
            .arrow_down => self.inspectorScrollDown(),
            .page_up => self.inspectorPageUp(),
            .page_down => self.inspectorPageDown(),
            .escape => {
                self.view_mode = .overview;
                self.needs_full_render = true;
                self.needs_redraw = true;
                self.inspector_scroll = 0;
                self.inspector_view = .output; // reset inspector view
            },
            .home => self.inspectorScrollToStart(),
            .end => self.inspectorScrollToEnd(),
            .mouse => |mouse_event| {
                switch (mouse_event.button) {
                    .scroll_up => self.inspectorScrollUp(),
                    .scroll_down => self.inspectorScrollDown(),
                    // TODO: allow selecting input/output with mouse & copy
                    else => {},
                }
            },
            else => {},
        }
    }

    fn handleHelpInput(self: *Self, key: tui.KeyEvent) !void {
        switch (key) {
            .char => |ch| switch (ch) {
                'q', 'Q' => self.quit_requested = true,
                else => {},
            },
            .escape => {
                self.view_mode = .overview;
                self.needs_full_render = true;
                self.needs_redraw = true;
            },
            else => {},
        }
    }

    fn moveUp(self: *Self) void {
        if (self.selected_stage > 0) {
            self.selected_stage -= 1;
            self.adjustScrollForSelection();
            self.needs_redraw = true;
        }
    }

    fn moveDown(self: *Self) void {
        if (self.selected_stage + 1 < self.pipeline.stages.items.len) {
            self.selected_stage += 1;
            self.adjustScrollForSelection();
            self.needs_redraw = true;
        }
    }

    fn pageUp(self: *Self) void {
        const page_size = (self.terminal.height - 6) / 4; // 4 lines per stage
        const scroll_offset = if (self.scroll_offset >= page_size)
            self.scroll_offset - page_size
        else
            0;

        if (self.setScrollOffset(scroll_offset)) {
            self.adjustSelectionForScroll();
            self.needs_full_render = true;
        }
    }

    fn pageDown(self: *Self) void {
        const page_size = (self.terminal.height - 6) / 4; // 4 lines per stage
        const max_scroll = if (self.pipeline.stages.items.len > page_size)
            self.pipeline.stages.items.len - page_size
        else
            0;

        const scroll_offset = if (self.scroll_offset + page_size <= max_scroll)
            self.scroll_offset + page_size
        else
            max_scroll;

        if (self.setScrollOffset(scroll_offset)) {
            self.adjustSelectionForScroll();
            self.needs_full_render = true;
        }
    }

    fn adjustScrollForSelection(self: *Self) void {
        const visible_stages = (self.terminal.height - 6) / 4;

        if (self.selected_stage < self.scroll_offset) {
            self.scroll_offset = self.selected_stage;
            self.needs_full_render = true;
        } else if (self.selected_stage >= self.scroll_offset + visible_stages) {
            self.scroll_offset = self.selected_stage - visible_stages + 1;
            self.needs_full_render = true;
        }
    }

    fn adjustSelectionForScroll(self: *Self) void {
        const visible_stages = (self.terminal.height - 6) / 4;

        if (self.selected_stage < self.scroll_offset) {
            self.selected_stage = self.scroll_offset;
            self.needs_full_render = true;
        } else if (self.selected_stage >= self.scroll_offset + visible_stages) {
            self.selected_stage = @min(self.pipeline.stages.items.len - 1, self.scroll_offset + visible_stages - 1);
            self.needs_full_render = true;
        }
    }

    fn inspectorScrollUp(self: *Self) void {
        const inspector_scroll = if (self.inspector_scroll > 0)
            self.inspector_scroll - 1
        else
            0;

        _ = self.setInspectorScroll(inspector_scroll);
    }

    fn inspectorScrollDown(self: *Self) void {
        const stage = &self.pipeline.stages.items[self.selected_stage];
        const data = switch (self.inspector_view) {
            .input => stage.input_data,
            .output => if (stage.status == .@"error") stage.error_msg.? else stage.output_data,
        };
        const total_lines = std.mem.count(u8, data, "\n") + 1;
        const display_height = self.terminal.height - 7;
        const max_scroll = if (total_lines > display_height) total_lines - display_height + 1 else 0;

        const inspector_scroll = if (self.inspector_scroll < max_scroll)
            self.inspector_scroll + 1
        else
            max_scroll;

        _ = self.setInspectorScroll(inspector_scroll);
    }

    fn inspectorPageUp(self: *Self) void {
        const page_size = self.terminal.height - 7;
        const inspector_scroll = if (self.inspector_scroll >= page_size)
            self.inspector_scroll - page_size
        else
            0;

        _ = self.setInspectorScroll(inspector_scroll);
    }

    fn inspectorPageDown(self: *Self) void {
        const display_height = self.terminal.height - 7;
        const page_size = display_height;
        const stage = &self.pipeline.stages.items[self.selected_stage];
        const data = switch (self.inspector_view) {
            .input => stage.input_data,
            .output => if (stage.status == .@"error") stage.error_msg.? else stage.output_data,
        };
        const total_lines = std.mem.count(u8, data, "\n") + 1;
        const max_scroll = if (total_lines > display_height) total_lines - display_height + 1 else 0;

        const inspector_scroll = if (self.inspector_scroll + page_size < max_scroll)
            self.inspector_scroll + page_size
        else
            max_scroll;

        _ = self.setInspectorScroll(inspector_scroll);
    }

    fn inspectorScrollToStart(self: *Self) void {
        _ = self.setInspectorScroll(0);
    }

    fn inspectorScrollToEnd(self: *Self) void {
        const display_height = self.terminal.height - 7;
        const stage = &self.pipeline.stages.items[self.selected_stage];

        const data = switch (self.inspector_view) {
            .input => stage.input_data,
            .output => if (stage.status == .@"error") stage.error_msg.? else stage.output_data,
        };
        const total_lines = std.mem.count(u8, data, "\n") + 1;
        const max_scroll = if (total_lines > display_height) total_lines - display_height else 0;

        _ = self.setInspectorScroll(max_scroll + 1);
    }

    pub fn rerunFromStage(self: *Self) !void {
        if (self.pipeline.stages.items.len == 0) return;

        // Reset stages from selected onwards
        for (self.pipeline.stages.items[self.selected_stage..]) |*stage| {
            stage.status = .pending;
            if (stage.output_data.len > 0) {
                self.allocator.free(stage.output_data);
                stage.output_data = &[_]u8{};
            }
            if (stage.error_msg) |err| {
                self.allocator.free(err);
                stage.error_msg = null;
            }
        }

        // Start execution in background
        try self.executePipeline(self.selected_stage);
    }

    pub fn rerunPipeline(self: *Self) !void {
        // Reset all stages
        for (self.pipeline.stages.items) |*stage| {
            stage.status = .pending;
            if (stage.output_data.len > 0) {
                self.allocator.free(stage.output_data);
                stage.output_data = &[_]u8{};
            }
            if (stage.error_msg) |err| {
                self.allocator.free(err);
                stage.error_msg = null;
            }
        }

        self.selected_stage = 0;
        self.scroll_offset = 0;

        try self.executePipeline(0);
    }

    pub fn executePipeline(self: *Self, start_stage: usize) !void {
        const ctx = self.allocator.create(PipelineContext) catch @panic("Failed to allocate PipelineContext");
        defer self.allocator.destroy(ctx);

        ctx.* = .{
            .app = self,
            .start_stage = start_stage,
        };

        _ = try Thread.spawn(.{}, pipelineThreadFn, .{ctx});
    }

    fn pipelineThreadFn(ctx: *PipelineContext) void {
        const app = ctx.app;
        const start_stage = ctx.start_stage;

        app.app_mutex.lock();
        app.needs_redraw = true;
        app.app_mutex.unlock();

        var current_data: []u8 = &[_]u8{};
        if (start_stage > 0) {
            app.app_mutex.lock();
            current_data = app.pipeline.stages.items[start_stage - 1].output_data;
            app.app_mutex.unlock();
        }

        for (app.pipeline.stages.items[start_stage..], start_stage..) |*stage, i| {
            app.app_mutex.lock();
            stage.status = .running;
            app.needs_redraw = true;
            _ = app.stages_to_rerender.append(i) catch {};
            app.app_mutex.unlock();

            app.pipeline.executor.executeStage(stage, current_data) catch {
                app.app_mutex.lock();
                stage.status = .@"error";
                stage.error_msg = "Failed to execute stage";
                app.app_mutex.unlock();
            };
            current_data = stage.output_data;

            app.app_mutex.lock();
            app.needs_redraw = true;
            _ = app.stages_to_rerender.append(i) catch {};
            app.app_mutex.unlock();

            // small delay to show the transition
            std.time.sleep(50_000_000);
        }

        app.app_mutex.lock();
        app.needs_redraw = true;
        app.app_mutex.unlock();
    }

    fn saveOutput(self: *Self) !void {
        if (self.pipeline.stages.items.len == 0 or self.selected_stage >= self.pipeline.stages.items.len) return;

        const stage = &self.pipeline.stages.items[self.selected_stage];
        if (stage.output_data.len == 0) return;

        var filename_buf: [256]u8 = undefined;
        const filename = try std.fmt.bufPrint(filename_buf[0..], "pipeline_stage_{}_output.txt", .{self.selected_stage + 1});

        const file = std.fs.cwd().createFile(filename, .{}) catch return;
        defer file.close();

        try file.writeAll(stage.output_data);
    }

    fn togglePause(self: *Self) !void {
        // TODO: Implementation for pausing/resuming pipeline execution
        _ = self;
    }

    fn hasRunningStages(self: *const Self) bool {
        for (self.pipeline.stages.items) |stage| {
            if (stage.status == .running) {
                return true;
            }
        }
        return false;
    }
};

const std = @import("std");
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const glue = @import("glue");
const Pipeline = glue.Pipeline;
const Stage = glue.Stage;
const tui = glue.tui;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
