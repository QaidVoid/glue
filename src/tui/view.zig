pub fn render(app: *App) !void {
    switch (app.view_mode) {
        .overview => try renderOverview(app),
        .inspector => try renderInspector(app),
        .help => try renderHelp(app),
    }

    try renderStatusBar(app);
}

fn renderOverview(app: *App) !void {
    const term = &app.terminal;
    const stage_height = 4;

    if (app.needs_full_render) {
        try term.clearArea(0, term.height - 2);
    }

    try term.moveTo(0, 0);
    const title_style = Style{ .fg = .black, .bg = .cyan, .bold = true };
    try title_style.apply(term);

    const title = "GLUE - Interactive Pipeline Visualizer";
    const padding = (term.width - title.len) / 2;

    for (0..term.width) |_| try term.stdout.writeAll(" ");
    try term.moveTo(0, padding);
    try term.stdout.writeAll(title);
    try (Style{ .fg = .reset }).apply(term);

    const visible_stages = (term.height - 6) / stage_height;
    const start_idx = app.scroll_offset;
    const end_idx = @min(app.pipeline.stages.items.len, start_idx + visible_stages);

    // This is the main rendering function for the overview screen. It handles three
    // main scenarios to optimize performance:
    //   1. needs_full_render: When the entire screen needs to be redrawn, such as
    //      on the first render or switching views.
    //   2. selected_stage change: When only the selected stage changes, we only
    //      redraw the previously selected and the newly selected stages to avoid
    //      flickering and unnecessary redraws.
    //   3. running stage update: When a stage is running, we only redraw that
    //      specific stage to show its status change.
    if (app.needs_full_render) {
        for (app.pipeline.stages.items[start_idx..end_idx], 0..) |*stage, i| {
            const stage_idx = start_idx + i;
            const y_pos = @as(u16, @intCast(2 + i * stage_height));
            try renderStage(app, stage, y_pos, stage_idx, stage_idx == app.selected_stage);
        }
        app.needs_full_render = false;
    } else if (app.selected_stage != app.last_selected_stage) {
        const last_visible = app.last_selected_stage >= start_idx and app.last_selected_stage < end_idx;
        const current_visible = app.selected_stage >= start_idx and app.selected_stage < end_idx;

        if (last_visible) {
            const y_pos = @as(u16, @intCast(2 + (app.last_selected_stage - start_idx) * stage_height));
            try renderStage(app, &app.pipeline.stages.items[app.last_selected_stage], y_pos, app.last_selected_stage, false);
        }
        if (current_visible) {
            const y_pos = @as(u16, @intCast(2 + (app.selected_stage - start_idx) * stage_height));
            try renderStage(app, &app.pipeline.stages.items[app.selected_stage], y_pos, app.selected_stage, true);
        }
    } else {
        for (app.pipeline.stages.items[start_idx..end_idx], 0..) |*stage, i| {
            if (stage.status == .running) {
                const stage_idx = start_idx + i;
                const y_pos = @as(u16, @intCast(2 + i * stage_height));
                try renderStage(app, stage, y_pos, stage_idx, stage_idx == app.selected_stage);
            }
        }
    }

    // The executor runs in a separate thread and updates the stage statuses. To avoid
    // race conditions and ensure thread safety, the executor pushes the indices of
    // stages that need to be rerendered to a thread-safe queue. The rendering loop
    // then processes this queue and redraws only the necessary stages.
    app.app_mutex.lock();
    if (app.stages_to_rerender.items.len > 0) {
        for (app.stages_to_rerender.items) |stage_idx| {
            if (stage_idx >= start_idx and stage_idx < end_idx) {
                const y_pos = @as(u16, @intCast(2 + (stage_idx - start_idx) * stage_height));
                try renderStage(app, &app.pipeline.stages.items[stage_idx], y_pos, stage_idx, stage_idx == app.selected_stage);
            }
        }
        app.stages_to_rerender.clearRetainingCapacity();
    }
    app.app_mutex.unlock();

    app.last_selected_stage = app.selected_stage;

    const scroll_area = tui.Rect{ .x = 0, .y = 0, .width = term.width, .height = term.height - 3 };
    try render_scroll_indicators(
        &app.terminal,
        scroll_area,
        app.scroll_offset,
        app.pipeline.stages.items.len,
        visible_stages,
    );
}

fn render_scroll_indicators(
    term: *Terminal,
    area: tui.Rect,
    scroll_pos: usize,
    total_items: usize,
    visible_items: usize,
) !void {
    const indicator_style = Style{ .fg = .bright_yellow };
    const x_pos = area.x + area.width - 3;

    // Clear previous up indicator
    try term.moveTo(area.y + 1, x_pos);
    try term.stdout.writeAll(" ");

    if (scroll_pos > 0) {
        try term.moveTo(area.y + 1, x_pos);
        try indicator_style.apply(term);
        try term.stdout.writeAll("▲");
    }

    // Clear previous down indicator
    try term.moveTo(area.y + area.height - 2, x_pos);
    try term.stdout.writeAll(" ");

    if (scroll_pos + visible_items < total_items) {
        try term.moveTo(area.y + area.height - 2, x_pos);
        try indicator_style.apply(term);
        try term.stdout.writeAll("▼");
    }
    try (Style{ .fg = .reset }).apply(term);
}

fn renderStage(app: *App, stage: *const Stage, y: u16, stage_idx: usize, is_selected: bool) !void {
    const term = &app.terminal;
    const box_width = term.width - 4;
    const box_height = 4;

    const border_style = if (is_selected)
        tui.Style{ .fg = .cyan, .bold = true }
    else
        tui.Style{ .fg = .bright_black };

    var title_buf: [64]u8 = undefined;
    const title = try std.fmt.bufPrint(&title_buf, "Stage {}", .{stage_idx + 1});

    const stage_rect = tui.Rect{ .x = 2, .y = y, .width = box_width, .height = box_height };
    try tui.drawBox(&app.terminal, stage_rect, title, border_style, .rounded);

    const content_rect = stage_rect.inner(1);

    try term.moveTo(content_rect.y, content_rect.x);

    const status_char = switch (stage.status) {
        .pending => "",
        .running => getHourglassFrame(app.animation_tick),
        .completed => "",
        .@"error" => "",
    };
    const status_color = switch (stage.status) {
        .pending => Color.yellow,
        .running => Color.bright_blue,
        .completed => Color.green,
        .@"error" => Color.red,
    };

    try (tui.Style{ .fg = status_color }).apply(term);
    try term.stdout.writeAll(status_char);
    try (tui.Style{ .fg = .white }).apply(term);

    try term.stdout.writer().print(" {s}", .{stage.command});

    const used_space = 2 + 1 + stage.command.len; // emoji(2) + space(1) + command
    if (content_rect.width > used_space) {
        const padding = content_rect.width - used_space;
        for (0..padding) |_| try term.stdout.writeAll(" ");
    }

    try term.moveTo(content_rect.y + 1, content_rect.x);
    var used_space_line2: usize = 0;

    if (stage.status == .running) {
        const running_text = " Running...";
        try term.stdout.writeAll(running_text);
        used_space_line2 = running_text.len;
    } else if (stage.status == .completed) {
        var time_buf: [20]u8 = undefined;
        const time_str = try std.fmt.bufPrint(&time_buf, " {}ms", .{stage.execution_time});

        var size_buf: [30]u8 = undefined;
        const size_str = try std.fmt.bufPrint(&size_buf, "󱀩 {} bytes", .{stage.data_size});

        const total_len = time_str.len + size_str.len + 2;
        const padding = if (content_rect.width > total_len) content_rect.width - total_len else 0;

        for (0..padding) |_| try term.stdout.writeAll(" ");

        try (tui.Style{ .fg = .cyan }).apply(term);
        try term.stdout.writeAll(time_str);

        try (tui.Style{ .fg = .magenta }).apply(term);
        try term.stdout.writeAll("  ");
        try term.stdout.writeAll(size_str);
        used_space_line2 = content_rect.width;
    } else if (stage.status == .@"error" and stage.error_msg != null) {
        try (tui.Style{ .fg = .red }).apply(term);
        const error_str = "Error (press 'i' to inspect)";
        try term.stdout.writeAll(error_str);
        used_space_line2 = error_str.len;
    }

    if (content_rect.width > used_space_line2) {
        const padding = content_rect.width - used_space_line2;
        for (0..padding) |_| try term.stdout.writeAll(" ");
    }
}

fn renderInspector(app: *App) !void {
    const term = &app.terminal;
    try term.clearArea(0, term.height - 2);

    if (app.pipeline.stages.items.len == 0 or app.selected_stage >= app.pipeline.stages.items.len) {
        try term.moveTo(term.height / 2, 10);
        try (Style{ .fg = .red }).apply(term);
        try term.stdout.writeAll("No stage selected for inspection");
        return;
    }

    const stage = &app.pipeline.stages.items[app.selected_stage];

    try term.moveTo(0, 0);
    try (Style{ .fg = .bright_cyan, .bold = true }).apply(term);
    try term.stdout.writer().print("🔍 DATA INSPECTOR - Stage {} of {}", .{ app.selected_stage + 1, app.pipeline.stages.items.len });

    try term.moveTo(1, 0);
    try (Style{ .fg = .white }).apply(term);
    try term.stdout.writer().print("Command: {s}", .{stage.command});

    try term.moveTo(3, 2);
    const input_style = if (app.inspector_view == .input)
        Style{ .fg = .black, .bg = .yellow, .bold = true }
    else
        Style{ .fg = .yellow };

    const output_style = if (app.inspector_view == .output)
        Style{ .fg = .black, .bg = .green, .bold = true }
    else
        Style{ .fg = .green };

    const error_style = if (stage.status == .@"error" and app.inspector_view == .output)
        Style{ .fg = .black, .bg = .red, .bold = true }
    else
        Style{ .fg = .red };

    try input_style.apply(term);
    try term.stdout.writeAll(" INPUT ");
    try (Style{ .fg = .white }).apply(term);

    if (stage.status == .@"error") {
        try (Style{ .fg = .white }).apply(term);
        try error_style.apply(term);
        try term.stdout.writeAll(" ERROR ");
    } else {
        try term.stdout.writeAll(" │ ");
        try output_style.apply(term);
        try term.stdout.writeAll(" OUTPUT ");
    }

    try (Style{ .fg = .reset }).apply(term);

    const data = switch (app.inspector_view) {
        .input => stage.input_data,
        .output => if (stage.status == .@"error") stage.error_msg.? else stage.output_data,
    };

    const display_start = 5;
    const box_height = term.height - display_start - 1;
    const box_width = term.width;
    const box_y = display_start - 1;

    const inspector_rect = tui.Rect{ .x = 0, .y = box_y, .width = box_width, .height = box_height };
    try tui.drawBox(&app.terminal, inspector_rect, null, tui.Style{ .fg = .bright_black }, .rounded);

    const content_rect = inspector_rect.inner(1);
    const display_height = content_rect.height;

    if (data.len == 0) {
        try term.moveTo(content_rect.y, content_rect.x);
        try (Style{ .fg = .bright_black, .italic = true }).apply(term);
        try term.stdout.writeAll("(empty)");
    } else {
        var lines = std.mem.splitScalar(u8, data, '\n');
        var line_count: usize = 0;
        var displayed_lines: usize = 0;

        // Skip scrolled lines
        while (line_count < app.inspector_scroll and lines.next() != null) {
            line_count += 1;
        }

        // Render visible lines
        while (lines.next()) |line| {
            if (displayed_lines >= display_height) break;

            try term.moveTo(content_rect.y + displayed_lines, content_rect.x);
            try (Style{ .fg = .bright_black }).apply(term);
            try term.stdout.writer().print("{:4} ", .{line_count + 1});

            if (stage.status == .@"error" and app.inspector_view == .output) {
                try (Style{ .fg = .red }).apply(term);
            } else {
                try (Style{ .fg = .white }).apply(term);
            }

            const max_line_width = content_rect.width - 6;
            var current_line_len: usize = 0;
            var remainder = line;

            while (remainder.len > 0) {
                // Find the next break (space-delimited word or full chunk)
                const delimiter_pos = std.mem.indexOfScalar(u8, remainder, ' ');
                const chunk_end = delimiter_pos orelse remainder.len;
                var chunk = remainder[0..chunk_end];

                // If the chunk is larger than the available width, split it directly
                while (chunk.len > 0) {
                    const space_left = max_line_width - current_line_len;
                    const to_write = @min(space_left, chunk.len);

                    try term.stdout.writeAll(chunk[0..to_write]);
                    current_line_len += to_write;

                    if (current_line_len >= max_line_width) {
                        displayed_lines += 1;
                        if (displayed_lines >= display_height) break;

                        try term.moveTo(content_rect.y + displayed_lines, content_rect.x);
                        try (Style{ .fg = .bright_black }).apply(term);
                        try term.stdout.writeAll("      ");
                        try (Style{ .fg = .white }).apply(term);

                        current_line_len = 0;
                    }

                    chunk = chunk[to_write..];
                }

                if (displayed_lines >= display_height) break;

                // Skip delimiter (space) if any
                if (delimiter_pos) |pos| {
                    remainder = remainder[pos + 1 ..];
                    if (current_line_len < max_line_width) {
                        try term.stdout.writeAll(" ");
                        current_line_len += 1;
                    } else {
                        displayed_lines += 1;
                        if (displayed_lines >= display_height) break;

                        try term.moveTo(content_rect.y + displayed_lines, content_rect.x);
                        try (Style{ .fg = .bright_black }).apply(term);
                        try term.stdout.writeAll("      ");
                        try (Style{ .fg = .white }).apply(term);
                        current_line_len = 0;
                    }
                } else {
                    remainder = remainder[chunk_end..];
                }
            }

            displayed_lines += 1;
            line_count += 1;
        }
    }

    const total_lines = std.mem.count(u8, data, "\n") + 1;
    try render_scroll_indicators(
        &app.terminal,
        inspector_rect,
        app.inspector_scroll,
        total_lines,
        display_height,
    );
}

fn renderHelp(app: *App) !void {
    const term = &app.terminal;
    try term.clearArea(0, term.height - 2);

    try term.moveTo(0, 0);
    try (Style{ .fg = .bright_cyan, .bold = true }).apply(term);
    try term.stdout.writeAll("🆘 HELP - Interactive Pipeline Visualizer");

    const help_items = keymap.keymap;

    var y: u16 = 3;
    for (help_items) |item| {
        try term.moveTo(y, 4);
        try (Style{ .fg = .bright_yellow, .bold = true }).apply(term);
        try term.stdout.writer().print("{s:<15}", .{item.key});
        try (Style{ .fg = .white }).apply(term);
        try term.stdout.writer().print(" - {s}", .{item.description});
        y += 1;
    }

    y += 2;
    try term.moveTo(y, 4);
    try (Style{ .fg = .bright_green }).apply(term);
    try term.stdout.writeAll("💡 Tips:");
    y += 1;

    const tips = [_][]const u8{
        "• Use the data inspector to examine input/output at each stage",
        "• Re-run from any stage to debug pipeline issues",
        "• Pipeline execution continues in the background",
    };

    for (tips) |tip| {
        try term.moveTo(y, 6);
        try (Style{ .fg = .cyan }).apply(term);
        try term.stdout.writeAll(tip);
        y += 1;
    }
}

fn renderStatusBar(app: *App) !void {
    const term = &app.terminal;
    const status_y = term.height - 1;

    try term.moveTo(status_y, 0);
    try term.stdout.writeAll("\x1B[K"); // Clear entire line

    try (Style{ .fg = .black, .bg = .white }).apply(term);

    for (0..term.width) |_| try term.stdout.writeAll(" ");

    try term.moveTo(status_y, 1);

    var left_buf: [256]u8 = undefined;
    const left_text = try buildLeftStatus(app, &left_buf);
    try term.stdout.writeAll(left_text);

    // Right-aligned info
    const right_text = getRightStatus(app);
    const right_start = term.width - right_text.len - 1;
    if (right_start > left_text.len) {
        try term.moveTo(status_y, right_start);
        try term.stdout.writeAll(right_text);
    }

    try (Style{ .fg = .reset }).apply(term);
}

fn buildLeftStatus(app: *App, buffer: []u8) ![]const u8 {
    var fbs = std.io.fixedBufferStream(buffer);
    const writer = fbs.writer();

    const status_text = switch (app.view_mode) {
        .overview => "OVERVIEW",
        .inspector => "INSPECTOR",
        .help => "HELP",
    };

    try writer.print(" {s} ", .{status_text});

    if (app.pipeline.stages.items.len > 0) {
        try writer.print("│ Stage {}/{} ", .{ app.selected_stage + 1, app.pipeline.stages.items.len });

        const current_stage = &app.pipeline.stages.items[app.selected_stage];
        const stage_status = switch (current_stage.status) {
            .pending => "PENDING",
            .running => "RUNNING",
            .completed => "COMPLETED",
            .@"error" => "ERROR",
        };

        try writer.print("│ {s} ", .{stage_status});
    }

    return fbs.getWritten();
}

fn getRightStatus(app: *App) []const u8 {
    return switch (app.view_mode) {
        .overview => "[h] Help [i] Inspect [q] Quit",
        .inspector => "[Tab] Switch [c] Copy [Esc] Back [q] Quit",
        .help => "[Esc] Back [q] Quit",
    };
}

fn getHourglassFrame(tick: u8) []const u8 {
    const frames = [_][]const u8{ "", "", "" };
    return frames[tick % frames.len];
}

const std = @import("std");
const glue = @import("glue");

const tui = glue.tui;

const App = glue.App;
const Stage = glue.Stage;
const Terminal = tui.Terminal;
const Style = tui.Style;
const Color = tui.Color;
const keymap = @import("./keymap.zig");
