# CourseS

A tiny macOS menu bar app for tracking your courses. Click the 📚 icon in the menu bar, and a panel drops down (like the Wi-Fi / Bluetooth panels). Click the icon again to close it.

Each course is a column, with up to 8 in a row. Further courses start a new row below.

- **Key dates** above the course name. Add them with **+**, and each one shows a countdown (orange within a week, red within 2 days).
- **Course name**, **current status** and **notes**.
- Reorder courses with the ‹ › arrows or by dragging ⠿.
- Pin 📌 the panel to keep it open while you work in other apps.

## Your data is never lost

- Every edit is auto-saved to `~/Library/Application Support/CourseS/courses.json`, and saved again on quit.
- A daily snapshot is kept for 30 days in `Snapshots/`. If the main file is ever damaged, the newest snapshot is loaded instead.
- The app refuses to overwrite existing courses with empty data.
- Deleted courses can be undone, or restored later from *Recently deleted*.

## Lightweight

- Native Swift app shell with a WebKit UI.
- No Dock icon, no timers and no background work.
- Uses about 0% CPU when idle.

## Build

Requires macOS 13+ and the Xcode command line tools.

```sh
./build.sh          # produces CourseS.app
open CourseS.app
```

To launch it at login, add `CourseS.app` in System Settings → General → Login Items.

## Project layout

| File | Purpose |
| --- | --- |
| `src/main.swift` | Menu bar item, drop-down panel, saving to disk |
| `src/index.html` | The whole UI (HTML/CSS/JS, no dependencies) |
| `src/icon.swift` | Draws the app icon at build time |
| `build.sh` | Compiles and bundles `CourseS.app` |
