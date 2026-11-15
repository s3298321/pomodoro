# Pomodoro

A small tomato that sits in a corner of the screen and keeps time while you work.

Click it to start a study session. It begins green and ripens toward red as the minutes pass. Hover to see the countdown. When the session ends, it asks whether you want a break. Drag it to any corner and it stays there.

Pomodoro is a borderless macOS panel. It has no Dock icon, floats above other windows, and follows you across Spaces.

## Use it

| Action | What happens |
| --- | --- |
| Click the tomato | Starts a study session (25 minutes by default). |
| Hover during study | The tomato opens into a pill with the time left and a Stop button. Move the pointer away and it closes again. |
| Stop | Ends the session and returns to the tomato. |
| Wait until the timer ends | A prompt asks **Take a break?** Yes starts the pause (5 minutes by default). No returns to the tomato. |
| Right-click | Opens settings. Set study length (1–180 minutes) and pause length (1–60 minutes), or quit. Click elsewhere, press Escape, or right-click again to close. |
| Drag | Carry the widget to another corner. On release it glides into place and remembers that corner. |

Durations and the chosen corner are saved and restored the next time you open the app.

Quit from the settings card, or press **⌘Q**.

## Requirements

- macOS 15.4 or later
- Swift Command Line Tools (`xcode-select --install`)

## Build and run

From the project root:

```bash
./scripts/build-app.sh
open Pomodoro.app
```

The script runs the model tests, compiles `Pomodoro.app`, and ad-hoc signs it. The app is a menu-bar-style accessory: look for the tomato in the bottom-left corner of the screen.

To try the flow without waiting out a full session, launch with short timers (five seconds each):

```bash
./scripts/build-app.sh
open Pomodoro.app --args -short-timers
```

## Project layout

```
Pomodoro/          Widget, panel, and timer model
PomodoroApp/       App entry point
PomodoroTests/     Model tests
scripts/build-app.sh
```

The timer logic lives in `PomodoroModel` and does not depend on the interface. The floating panel and the tomato drawing sit on top of it in AppKit and SwiftUI.

## License

[MIT](LICENSE)
