# Finder Sidebar Favorites: Technical Notes

## Background

macOS Finder's sidebar "Favorites" section can be managed programmatically, but Apple has made this increasingly difficult over successive releases by deprecating public APIs without replacements.

## Approaches Considered

### 1. AppleScript (`add to favorites`)

```applescript
tell application "Finder" to add to favorites (POSIX file "/path/to/folder" as alias)
```

- Talks to **Finder.app** via Apple Events (inter-process communication).
- The `add to favorites` verb is broken on macOS 26 (error `-1708`: Finder doesn't handle the message).
- Even when it worked, it could only **append** to the bottom — no reordering, listing, or removal.

### 2. AppleScript GUI Scripting (System Events)

- Uses accessibility APIs to simulate `Cmd+Ctrl+T` or click "Add to Sidebar" in File menu.
- Requires granting accessibility permissions to `osascript`.
- Fragile — breaks whenever Apple changes Finder's UI element hierarchy.

### 3. `mysides` CLI Tool

- Third-party C tool wrapping `LSSharedFileList` API.
- **Abandoned** (last release: September 2016). Removed from Homebrew October 2025.
- Segfaults on macOS Ventura+, broken on Sequoia.

### 4. `sfltool add-item` (Built-in)

- Apple provided `sfltool add-item` in macOS 10.11–10.12 only.
- **Removed in macOS 10.13 High Sierra** (2017). The `sfltool` binary still exists but only handles `dumpRecentItems`/`resetRecentItems`.

### 5. PyObjC + CoreServices (chosen approach)

Uses the `LSSharedFileList` C API via Python's built-in PyObjC bridge. This is what `finder.sh` uses.

## Architecture

The two approaches operate at different layers:

```
AppleScript path:                    PyObjC path (what we use):

osascript                            python3
  └─ Apple Events IPC                  └─ PyObjC bridge
       └─ Finder.app                        └─ CoreServices C framework
            └─ (internal, opaque)                └─ LSSharedFileList API
                                                      └─ reads/writes .sfl3 files
                                                           └─ Finder picks up changes
```

**AppleScript** asks Finder the application to perform an action on our behalf.
**PyObjC** bypasses Finder entirely and modifies the sidebar data store directly at the OS level.

## Key APIs Used

All from `CoreServices` framework (no third-party dependencies):

| Function | Purpose |
|----------|---------|
| `LSSharedFileListCreate` | Get a reference to the FavoriteItems list |
| `LSSharedFileListCopySnapshot` | Read all current sidebar items |
| `LSSharedFileListInsertItemURL` | Add a new item |
| `LSSharedFileListItemRemove` | Remove an item |
| `LSSharedFileListItemCopyResolvedURL` | Get the file path of an item |
| `LSSharedFileListItemCopyDisplayName` | Get the display name of an item |

The `Foundation` and `CoreServices` Python modules are **pre-installed** on every Mac as part of Apple's system Python framework. PyObjC is Apple's official Python-to-Objective-C bridge — these are not third-party packages.

## Data Storage

Finder sidebar favorites are stored in:
```
~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.FavoriteItems.sfl3
```

The `.sfl3` format uses `NSKeyedArchiver` encoding (proprietary binary plist). The `LSSharedFileList` API abstracts away the binary format — do not attempt to edit these files directly.

## Caveats

- The `LSSharedFileList` API was **deprecated in macOS 10.11** but the underlying C functions have not been removed as of macOS 26.3. Apple could remove them in a future release.
- Changes take effect immediately in Finder without needing to restart it.
