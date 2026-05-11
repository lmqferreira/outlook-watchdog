# outlook-watchdog

Monitoring tool for a bug in **New Outlook for Mac** (v16.110+) where closing the main window (⌘W) and clicking the dock icon to reopen it causes **zombie windows and WebKit process leaks** that grow unboundedly until Outlook is force-quit.

## The Bug

When using New Outlook for Mac (`IsRunningNewOutlook = 1`):

1. **⌘W hides the window** instead of destroying it — the window object and its WebContent process stay alive
2. **Clicking the dock icon** creates a **brand new window** instead of restoring the hidden one
3. **Old windows are never released** — not even via AppleScript `close`
4. Each close/reopen cycle leaks **~2-4 hidden windows**, **1-2 WebKit processes**, and **~120 MB of RAM**
5. Eventually, `applicationShouldHandleReopen:hasVisibleWindows:` **stops working entirely** — clicking the dock icon does nothing

### Evidence

One close/reopen cycle:

```
TIME        WINDOWS  VISIBLE  HIDDEN  WEBCONTENT  RAM
Loaded      2        1        1       10          609 MB
⌘W          2        0        2       10          614 MB   ← hidden, not destroyed
Dock click  4        1        3       11          627 MB   ← NEW window, old leaked
Settled     6        1        5       12          742 MB   ← +4 zombies, +2 procs
```

The only fix is ⌘Q and relaunch.

## What This Tool Does

`outlook-watchdog` is a lightweight macOS daemon that monitors Outlook's window state and reports zombie window accumulation:

```
[2026-05-11 16:13:04] windows: 41 (visible: 0, hidden: 41) | ZOMBIES: 37 (main: 18, companion: 19) | Outlook: 1586 MB, WebContent: 23 procs / 866 MB, total: 2452 MB
```

It polls Outlook via AppleScript, classifies windows (main/companion/reminder), tracks state changes, and reports deltas when zombies accumulate. It only logs when something changes — no spam.

## Install

```bash
# Build from source
git clone https://github.com/lmqferreira/outlook-watchdog.git
cd outlook-watchdog
swift build -c release
cp .build/release/outlook-watchdog /usr/local/bin/
```

## Usage

```bash
# Run in a terminal
outlook-watchdog

# Custom polling interval (default: 5 seconds)
outlook-watchdog --interval 3
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--interval <seconds>` | Polling interval | `5` |
| `--help` | Show help | |

## Architecture

```
OutlookWatchdogLib (library)
├── OutlookQuery.swift    — AppleScript window enumeration
├── ZombieDetector.swift  — Window classification + snapshot diffing
├── ProcessInfo.swift     — RSS/WebContent process monitoring
└── Logger.swift          — Timestamped logging

Sources/CLI/main.swift    — NSApplication.accessory daemon + polling timer
Tests/main.swift          — 39 unit tests for classification and detection
```

### Window Classification

| Category | Pattern | Expected | Zombie condition |
|----------|---------|----------|------------------|
| Main | Inbox, Calendar, Mail | 1 visible | >1 hidden |
| Companion | Empty name | 1 per main window | grows with zombies |
| Reminder | Contains "Reminder" | 0-1 | unlikely |

## Root Cause

The New Outlook for Mac is a WebKit-based app. Its `windowWillClose:` handler hides windows (`visible = false`) instead of releasing them, and `applicationShouldHandleReopen:hasVisibleWindows:` creates new window instances instead of restoring hidden ones. Each hidden window retains its `com.apple.WebKit.WebContent` process.

Classic Outlook (legacy/native) does not exhibit this bug, but Microsoft is deprecating it and modern M365 auth no longer works with it.

## Why Not Auto-Fix?

We exhaustively tested every programmatic method to close zombie windows. **All of them fail.**

| Method | Result |
|--------|--------|
| AppleScript `close` | Silently ignored |
| `set visible to true` then `close` | Silently ignored |
| AppleScript `delete` | Error (-1728) |
| `close saving no` | Silently ignored |
| JXA `close()` | Silently ignored |
| `close window id <N>` | Silently ignored |
| ⌘W keystroke via System Events | Window hides again (not destroyed) |
| Make visible + ⌘W keystroke | Window hides again (not destroyed) |
| AXCloseButton click via Accessibility | Window count unchanged |
| `set miniaturized` toggle | No effect |
| ScriptingBridge `closeSaving` | No effect |
| ObjC `performClose:` | Cannot access another process's NSWindows |

The New Outlook's WebKit windows override all standard NSWindow close mechanisms. The `windowShouldClose:` delegate (or equivalent) vetoes destruction and sets `visible = false` instead.

**The only way to free zombie windows is ⌘Q and relaunch.**

## Requirements

- macOS 13+
- Swift 5.9+ (to build)
- Microsoft Outlook for Mac (New Outlook)

## License

MIT
