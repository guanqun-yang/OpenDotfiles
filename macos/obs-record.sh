# Record a specific app with OBS (audio + video isolation)
# Usage: obs-record  — interactive window picker via fzf
obs-record() {
    local OBS_SCENES="$HOME/Library/Application Support/obs-studio/basic/scenes/Untitled.json"

    # Check OBS is not running
    if pgrep -x OBS > /dev/null 2>&1; then
        echo "Error: OBS is running. Quit OBS first."
        return 1
    fi

    # List all windows + full screen option: "WindowID\tAppName\tTitle"
    local SELECTION
    SELECTION=$(cat << 'SWIFT' | swift - | fzf --delimiter='\t' --with-nth=2,3 --height=50% --layout=reverse --header="Select window to record"
import CoreGraphics

// Full screen option first
print("0\t[Full Screen]\tEntire display")

let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]

var bestWindows: [String: (id: Int, title: String, area: Int)] = [:]
let ignore: Set<String> = ["Window Server", "AutoFill", "CursorUIViewService", "Dock",
    "Control Centre", "Control Center", "SystemUIServer", "Spotlight",
    "TextInputMenuAgent", "universalAccessAuthWarn", "loginwindow"]

for w in windows {
    guard let owner = w["kCGWindowOwnerName"] as? String,
          !ignore.contains(owner),
          let layer = w["kCGWindowLayer"] as? Int, layer == 0,
          let wid = w["kCGWindowNumber"] as? Int,
          let bounds = w["kCGWindowBounds"] as? [String: Any],
          let width = bounds["Width"] as? Int, let height = bounds["Height"] as? Int,
          width >= 200, height >= 200 else { continue }
    let area = width * height
    let title = w["kCGWindowName"] as? String ?? ""
    let key = "\(owner)\t\(title)"
    if bestWindows[key] == nil || area > bestWindows[key]!.area {
        bestWindows[key] = (wid, title, area)
    }
}

for (key, val) in bestWindows.sorted(by: { $0.key < $1.key }) {
    let parts = key.split(separator: "\t", maxSplits: 1)
    let owner = String(parts[0])
    let display = val.title.isEmpty ? "" : val.title
    print("\(val.id)\t\(owner)\t\(display)")
}
SWIFT
    ) || true

    if [ -z "$SELECTION" ]; then
        echo "Cancelled."
        return 1
    fi

    local WINDOW_ID APP_NAME BUNDLE_ID
    WINDOW_ID=$(echo "$SELECTION" | cut -f1)
    APP_NAME=$(echo "$SELECTION" | cut -f2)

    # Patch the OBS scene JSON
    if [ "$WINDOW_ID" = "0" ]; then
        # Full screen mode
        echo "Mode:      Full Screen"
        python3 << PYTHON
import json

with open("$OBS_SCENES", "r") as f:
    config = json.load(f)

for source in config["sources"]:
    if source["id"] == "screen_capture" and source["name"] == "macOS Screen Capture":
        source["settings"] = {"type": 0, "show_cursor": True, "hide_obs": False}
        source["muted"] = False
        source["mixers"] = 255
        print("Video: Full display capture with audio")

    if source["id"] == "mac_sck_audio_capture":
        source["name"] = "Desktop Audio"
        source["settings"] = {"type": 0}
        print("Audio: Desktop audio")

    if source["id"] == "coreaudio_input_capture":
        source["muted"] = True
        source["mixers"] = 0

    if source["id"] == "scene":
        for item in source["settings"].get("items", []):
            if item.get("name", "").endswith("Audio"):
                item["name"] = "Desktop Audio"

if "AuxAudioDevice1" in config:
    config["AuxAudioDevice1"]["muted"] = True
    config["AuxAudioDevice1"]["mixers"] = 0

with open("$OBS_SCENES", "w") as f:
    json.dump(config, f)

print("Config updated.")
PYTHON
    else
        # App window mode
        BUNDLE_ID=$(osascript -e "id of app \"$APP_NAME\"" 2>/dev/null) || {
            echo "Error: Could not find bundle ID for '$APP_NAME'."
            return 1
        }

        echo "App:       $APP_NAME"
        echo "Bundle ID: $BUNDLE_ID"
        echo "Window ID: $WINDOW_ID"

        python3 << PYTHON
import json

with open("$OBS_SCENES", "r") as f:
    config = json.load(f)

for source in config["sources"]:
    if source["id"] == "screen_capture" and source["name"] == "macOS Screen Capture":
        source["settings"]["type"] = 1
        source["settings"]["application"] = "$BUNDLE_ID"
        source["settings"]["window"] = $WINDOW_ID
        source["settings"]["show_cursor"] = True
        source["settings"]["hide_obs"] = False
        source["muted"] = True
        source["mixers"] = 0
        print(f"Video: Window {$WINDOW_ID} ($APP_NAME) — audio muted")

    if source["id"] == "mac_sck_audio_capture":
        source["name"] = "$APP_NAME Audio"
        source["settings"]["type"] = 1
        source["settings"]["application"] = "$BUNDLE_ID"
        print(f"Audio: $APP_NAME ($BUNDLE_ID)")

    if source["id"] == "coreaudio_input_capture":
        source["muted"] = True
        source["mixers"] = 0

    if source["id"] == "scene":
        for item in source["settings"].get("items", []):
            if item.get("name", "").endswith("Audio"):
                item["name"] = "$APP_NAME Audio"

if "AuxAudioDevice1" in config:
    config["AuxAudioDevice1"]["muted"] = True
    config["AuxAudioDevice1"]["mixers"] = 0

with open("$OBS_SCENES", "w") as f:
    json.dump(config, f)

print("Config updated.")
PYTHON
    fi

    # Launch OBS
    echo "Launching OBS..."
    open -a OBS
}
