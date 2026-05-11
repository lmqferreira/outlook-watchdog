## Bug: New Outlook for Mac leaks hidden windows and WebKit processes on every close/reopen cycle

### Summary

New Outlook for Mac (v16.110, macOS 15+) has a window lifecycle bug where closing the main window (⌘W) and reopening via dock click causes unbounded accumulation of hidden zombie windows and orphaned WebKit WebContent processes. Each cycle leaks approximately 120 MB of RAM. The leaked resources are never released until the application is fully quit (⌘Q).

### Environment

- Outlook for Mac version: 16.110 (Build 16.110.26050539)
- Bundle ID: com.microsoft.Outlook
- Mode: New Outlook (IsRunningNewOutlook = 1, RunningNewOutlook = 1)
- macOS: 15.x (Apple Silicon, arm64)

### Steps to Reproduce

1. Launch Outlook for Mac (New Outlook)
2. Wait for the main Inbox window to appear
3. Press ⌘W to close the main window (Outlook remains running in the Dock with the white dot indicator)
4. Click the Outlook icon in the Dock to reopen
5. Repeat steps 3-4

### Expected Behavior

- ⌘W should either destroy the window or hide it in a way that dock-click restores the same window
- No additional windows or processes should be created on reopen
- Memory usage should remain stable across close/reopen cycles

### Actual Behavior

Each close/reopen cycle:

1. ⌘W sets the window's `visible` property to `false` instead of destroying it. The NSWindow object and its associated WebContent process remain alive.
2. Clicking the Dock icon creates an entirely new window with new WebKit WebContent processes instead of restoring the hidden one.
3. The old hidden windows are never released. Even programmatic attempts to close them via AppleScript are ignored — `close` has no effect.
4. After enough cycles, `applicationShouldHandleReopen:hasVisibleWindows:` stops functioning entirely — clicking the Dock icon does nothing and no window appears.

### Measured Data

**Single close/reopen cycle (measured via AppleScript window enumeration and ps):**

| State          | Windows | Visible | Hidden | WebContent Procs | Outlook RSS |
|----------------|---------|---------|--------|------------------|-------------|
| After launch   | 2       | 1       | 1      | 10               | 609 MB      |
| After ⌘W       | 2       | 0       | 2      | 10               | 614 MB      |
| After dock click | 6     | 1       | 5      | 12               | 742 MB      |

**After extended use (multiple close/reopen cycles over a single session):**

| Metric               | Value        |
|----------------------|--------------|
| Total windows        | 48           |
| Visible windows      | 1            |
| Hidden (zombie) windows | 47        |
| Zombie main windows  | 22           |
| Zombie companion windows | 22       |
| Outlook process RSS  | 1,357 MB     |
| WebContent processes | 27           |
| WebContent total RSS | 1,014 MB     |
| **Total memory consumed** | **2,371 MB** |

All of this from a single Outlook session without quitting.

### Technical Analysis

The application binary at `/Applications/Microsoft Outlook.app/Contents/MacOS/Microsoft Outlook` contains the `applicationShouldHandleReopen:hasVisibleWindows:` selector, confirming the delegate is implemented. However, its implementation does not restore hidden windows — it appears to either create new instances or do nothing when zombie windows have accumulated.

Window enumeration via AppleScript (`tell application "Microsoft Outlook" to get windows`) confirms that closed windows persist with `visible = false`. These windows have valid IDs, names (e.g., "Inbox • user@example.com"), and are fully retained in memory. Each hidden window retains its associated `com.apple.WebKit.WebContent` XPC process.

AppleScript `close` commands targeting these windows by ID are silently ignored — the windows remain in the window list with no change in state.

Classic Outlook (legacy, non-WebKit) does not exhibit this behavior. However, Classic Outlook can no longer authenticate with Microsoft 365 Exchange accounts, making it not a viable workaround.

### Impact

- **Memory leak**: ~120 MB per close/reopen cycle, growing without bound
- **Process leak**: 1-2 orphaned WebContent (WebKit) processes per cycle
- **Broken UX**: Dock-click stops working after zombie accumulation, requiring a full ⌘Q/relaunch
- **System impact**: On machines where Outlook runs for days, this can consume multiple gigabytes of RAM

### Workaround

The only current workaround is to periodically quit Outlook (⌘Q) and relaunch it. Closing and reopening the window does not free resources.

### Root Cause (Likely)

The `windowWillClose:` (or equivalent) handler in the New Outlook for Mac hides windows by setting `visible = false` instead of calling `close` or `orderOut:` with proper release. The `applicationShouldHandleReopen:hasVisibleWindows:` handler creates new window instances instead of iterating existing windows to find and restore a hidden one.
