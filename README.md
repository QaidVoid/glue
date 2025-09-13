# glue

An interactive TUI-based pipeline visualizer for shell commands.

## Features

- **Interactive Visualization**: See your pipeline stages and their status in real-time.
- **Data Inspector**: Inspect the input, output, and errors of each stage.
- **Single Binary**: No dependencies required.

## Usage

Run `glue` with a pipeline string:

```sh
glue "cat data.csv | grep 'some value' | wc -l"
```

### Keybindings

| Key             | Description                               |
| --------------- | ----------------------------------------- |
| `↑`/`↓` or `j`/`k` | Navigate between stages                   |
| `Enter` or `i`  | Enter data inspector mode                 |
| `Tab`           | Switch between Input/Output in inspector  |
| `r`             | Re-run pipeline from selected stage       |
| `R`             | Re-run entire pipeline                    |
| `h` or `F1`     | Show/hide help                            |
| `Esc`           | Exit inspector/help mode                  |
| `q` or `Ctrl+C` | Quit application                          |

## Building

To build from source, you need the Zig compiler (0.15.1).

```sh
zig build
```
