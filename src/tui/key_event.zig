pub const MouseButton = enum {
    left,
    middle,
    right,
    scroll_up,
    scroll_down,
    mouse_move,
    none,
};

pub const MouseEvent = struct {
    x: u16,
    y: u16,
    button: MouseButton,
};

pub const KeyEvent = union(enum) {
    char: u8,
    arrow_up,
    arrow_down,
    arrow_left,
    arrow_right,
    page_up,
    page_down,
    home,
    end,
    enter,
    escape,
    tab,
    backspace,
    delete,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    unknown,
    mouse: MouseEvent,
};

pub fn parseKeyEvent(terminal: *Terminal) !KeyEvent {
    const key = try terminal.readKey();
    if (key == null) return KeyEvent.unknown;

    return switch (key.?) {
        27 => { // ESC sequence
            const next = try terminal.readKey();
            if (next == null) return KeyEvent.escape;

            return switch (next.?) {
                '[' => {
                    const seq_key = try terminal.readKey();
                    if (seq_key == null) return KeyEvent.unknown;

                    return switch (seq_key.?) {
                        'A' => KeyEvent.arrow_up,
                        'B' => KeyEvent.arrow_down,
                        'C' => KeyEvent.arrow_right,
                        'D' => KeyEvent.arrow_left,
                        'H' => KeyEvent.home,
                        'F' => KeyEvent.end,
                        'M' => { // Mouse event
                            const button_char = try terminal.readKey() orelse return KeyEvent.unknown;
                            const col_char = try terminal.readKey() orelse return KeyEvent.unknown;
                            const row_char = try terminal.readKey() orelse return KeyEvent.unknown;

                            const button: u8 = button_char - 32;
                            const x: u8 = col_char - 33;
                            const y: u8 = row_char - 33;

                            const mouse_button: MouseButton = switch (button) {
                                0 => .left,
                                1 => .middle,
                                2 => .right,
                                35 => .mouse_move,
                                64 => .scroll_up,
                                65 => .scroll_down,
                                else => .none,
                            };

                            return KeyEvent{ .mouse = .{
                                .x = @intCast(x),
                                .y = @intCast(y),
                                .button = mouse_button,
                            } };
                        },
                        '1' => {
                            const tilde = try terminal.readKey();
                            if (tilde != null and tilde.? == '~') return KeyEvent.home;
                            return KeyEvent.unknown;
                        },
                        '4' => {
                            const tilde = try terminal.readKey();
                            if (tilde != null and tilde.? == '~') return KeyEvent.end;
                            return KeyEvent.unknown;
                        },
                        '5' => {
                            const tilde = try terminal.readKey();
                            if (tilde != null and tilde.? == '~') return KeyEvent.page_up;
                            return KeyEvent.unknown;
                        },
                        '6' => {
                            const tilde = try terminal.readKey();
                            if (tilde != null and tilde.? == '~') return KeyEvent.page_down;
                            return KeyEvent.unknown;
                        },
                        '3' => {
                            const tilde = try terminal.readKey();
                            if (tilde != null and tilde.? == '~') return KeyEvent.delete;
                            return KeyEvent.unknown;
                        },
                        else => KeyEvent.unknown,
                    };
                },
                'O' => {
                    const function_key = try terminal.readKey();
                    if (function_key == null) return KeyEvent.unknown;

                    return switch (function_key.?) {
                        'P' => KeyEvent.f1,
                        'Q' => KeyEvent.f2,
                        'R' => KeyEvent.f3,
                        'S' => KeyEvent.f4,
                        else => KeyEvent.unknown,
                    };
                },
                else => KeyEvent.unknown,
            };
        },
        9 => KeyEvent.tab,
        10, 13 => KeyEvent.enter,
        127, 8 => KeyEvent.backspace,
        else => KeyEvent{ .char = key.? },
    };
}

const std = @import("std");
const Terminal = @import("glue").tui.Terminal;
