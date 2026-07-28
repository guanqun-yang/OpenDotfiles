# Clamshell / lid-close helper
# Keeps the laptop awake with lid closed, dims screen, kills backlights.

_LIDRUN_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/lidrun"

# ── Helpers ─────────────────────────────────────────────────────────

_lidrun_save() { local k="$1" v="$2"; mkdir -p "$_LIDRUN_STATE_DIR"; printf '%s' "$v" > "$_LIDRUN_STATE_DIR/$k"; }
_lidrun_load() { local f="$_LIDRUN_STATE_DIR/$1"; [[ -f "$f" ]] && cat "$f"; }

_lidrun_screen_brightness_linux() {
  local dir
  for dir in /sys/class/backlight/*/; do
    [[ -d "$dir" ]] || continue
    echo "$dir"
    return
  done
}

_lidrun_kbd_backlight_linux() {
  local dir="/sys/class/leds/platform::kbd_backlight"
  [[ -d "$dir" ]] && echo "$dir"
}

# ── On ──────────────────────────────────────────────────────────────

_lidrun_on_linux() {
  # 1. Inhibit lid switch via systemd-inhibit (no session restart needed)
  mkdir -p "$_LIDRUN_STATE_DIR"
  local pidfile="$_LIDRUN_STATE_DIR/inhibit.pid"
  if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    echo "  Lid switch: already inhibited (pid $(cat "$pidfile"))"
  else
    systemd-inhibit --what=handle-lid-switch --who="lidrun" \
      --why="Clamshell mode" --mode=block sleep infinity &
    echo $! > "$pidfile"
    echo "  Lid switch: inhibited (pid $!)"
  fi

  # 2. Prevent GNOME from locking/suspending on lid close
  if command -v gsettings &>/dev/null; then
    local schema="org.gnome.settings-daemon.plugins.power"
    local ac_prev bat_prev
    ac_prev=$(gsettings get "$schema" lid-close-ac-action 2>/dev/null)
    bat_prev=$(gsettings get "$schema" lid-close-battery-action 2>/dev/null)
    if [[ -n "$ac_prev" ]]; then
      _lidrun_save "lid_close_ac_action" "$ac_prev"
      _lidrun_save "lid_close_battery_action" "$bat_prev"
      gsettings set "$schema" lid-close-ac-action 'nothing'
      gsettings set "$schema" lid-close-battery-action 'nothing'
      echo "  GNOME lid actions: $ac_prev / $bat_prev -> 'nothing'"
    fi
  fi

  # 3. Dim screen backlight to minimum visible (save current value)
  local bl_dir
  bl_dir=$(_lidrun_screen_brightness_linux)
  if [[ -n "$bl_dir" ]]; then
    local cur max
    cur=$(cat "${bl_dir}brightness")
    max=$(cat "${bl_dir}max_brightness")
    _lidrun_save "screen_brightness" "$cur"
    # Set to 1 (not 0) so screen is nearly off but recoverable via brightness keys
    echo 1 | sudo tee "${bl_dir}brightness" > /dev/null
    echo "  Screen brightness: $cur -> 1 (max $max)"
    echo "  Tip: brightness keys still work to adjust manually"
  else
    echo "  Screen backlight: not found, skipping"
  fi

  # 4. Disable keyboard backlight
  local kbd_dir
  kbd_dir=$(_lidrun_kbd_backlight_linux)
  if [[ -n "$kbd_dir" ]]; then
    local cur
    cur=$(cat "${kbd_dir}/brightness")
    _lidrun_save "kbd_brightness" "$cur"
    echo 0 | sudo tee "${kbd_dir}/brightness" > /dev/null
    echo "  Keyboard backlight: $cur -> 0"
  else
    echo "  Keyboard backlight: not found, skipping"
  fi

  _lidrun_save "active" "1"
  echo "Clamshell mode ON. Safe to close the lid."
}

_lidrun_on_macos() {
  # 1. Prevent sleep on lid close
  echo "Disabling sleep on lid close (requires sudo)..."
  sudo pmset -a disablesleep 1
  echo "  Lid sleep: disabled"

  # 2. Turn off display (display sleeps but system stays awake)
  pmset displaysleepnow
  echo "  Display: sleeping"

  _lidrun_save "active" "1"
  echo "Clamshell mode ON. Safe to close the lid."
}

# ── Off ─────────────────────────────────────────────────────────────

_lidrun_off_linux() {
  # 1. Stop lid switch inhibitor
  local pidfile="$_LIDRUN_STATE_DIR/inhibit.pid"
  if [[ -f "$pidfile" ]]; then
    local pid
    pid=$(cat "$pidfile")
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null
      echo "  Lid switch: inhibitor stopped (pid $pid)"
    else
      echo "  Lid switch: inhibitor already gone"
    fi
    rm -f "$pidfile"
  else
    echo "  Lid switch: already at default"
  fi

  # 2. Restore GNOME lid actions
  if command -v gsettings &>/dev/null; then
    local schema="org.gnome.settings-daemon.plugins.power"
    local ac_prev bat_prev
    ac_prev=$(_lidrun_load "lid_close_ac_action")
    bat_prev=$(_lidrun_load "lid_close_battery_action")
    if [[ -n "$ac_prev" ]]; then
      gsettings set "$schema" lid-close-ac-action "$ac_prev"
      gsettings set "$schema" lid-close-battery-action "$bat_prev"
      echo "  GNOME lid actions: restored to $ac_prev / $bat_prev"
    fi
  fi

  # 3. Restore screen brightness
  local bl_dir prev
  bl_dir=$(_lidrun_screen_brightness_linux)
  prev=$(_lidrun_load "screen_brightness")
  if [[ -n "$bl_dir" && -n "$prev" ]]; then
    echo "$prev" | sudo tee "${bl_dir}brightness" > /dev/null
    echo "  Screen brightness: restored to $prev"
  fi

  # 4. Restore keyboard backlight
  local kbd_dir kbd_prev
  kbd_dir=$(_lidrun_kbd_backlight_linux)
  kbd_prev=$(_lidrun_load "kbd_brightness")
  if [[ -n "$kbd_dir" && -n "$kbd_prev" ]]; then
    echo "$kbd_prev" | sudo tee "${kbd_dir}/brightness" > /dev/null
    echo "  Keyboard backlight: restored to $kbd_prev"
  fi

  _lidrun_save "active" "0"
  echo "Clamshell mode OFF. Normal lid behavior restored."
}

_lidrun_off_macos() {
  # 1. Re-enable sleep on lid close
  echo "Re-enabling sleep on lid close (requires sudo)..."
  sudo pmset -a disablesleep 0
  echo "  Lid sleep: enabled"

  # 2. Display wakes automatically when lid opens or mouse/keyboard input
  echo "  Display: will wake on input"

  _lidrun_save "active" "0"
  echo "Clamshell mode OFF. Normal lid behavior restored."
}

# ── Status ──────────────────────────────────────────────────────────

_lidrun_status() {
  local active
  active=$(_lidrun_load "active")
  if [[ "$active" == "1" ]]; then
    echo "Clamshell mode: ON"
  else
    echo "Clamshell mode: OFF"
  fi

  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "  disablesleep: $(pmset -g | grep -i disablesleep | awk '{print $2}' 2>/dev/null || echo '?')"
  else
    local pidfile="$_LIDRUN_STATE_DIR/inhibit.pid"
    if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
      echo "  Lid switch: inhibited (pid $(cat "$pidfile"))"
    else
      echo "  Lid switch: default (suspend)"
    fi
    if command -v gsettings &>/dev/null; then
      local schema="org.gnome.settings-daemon.plugins.power"
      echo "  GNOME lid-close AC: $(gsettings get "$schema" lid-close-ac-action 2>/dev/null || echo '?')"
      echo "  GNOME lid-close battery: $(gsettings get "$schema" lid-close-battery-action 2>/dev/null || echo '?')"
    fi
    local bl_dir
    bl_dir=$(_lidrun_screen_brightness_linux)
    if [[ -n "$bl_dir" ]]; then
      echo "  Screen brightness: $(cat "${bl_dir}brightness") / $(cat "${bl_dir}max_brightness")"
    fi
    local kbd_dir
    kbd_dir=$(_lidrun_kbd_backlight_linux)
    if [[ -n "$kbd_dir" ]]; then
      echo "  Keyboard backlight: $(cat "${kbd_dir}/brightness")"
    fi
  fi
}

# ── Help ────────────────────────────────────────────────────────────

_lidrun_help() {
  echo "Usage: lidrun <command>"
  echo ""
  echo "Keep laptop running with lid closed (clamshell mode)."
  echo ""
  echo "Commands:"
  echo "  on      Enable clamshell mode (ignore lid, dim screen, kill backlights)"
  echo "  off     Restore normal lid behavior and brightness"
  echo "  status  Show current state"
  echo "  help    Show this help message"
  echo ""
  echo "Notes:"
  echo "  Linux:  Uses systemd-inhibit + sysfs backlight control (no session restart)"
  echo "  macOS:  Uses pmset disablesleep + displaysleepnow (needs sudo)"
}

# Run laptop with lid closed: lidrun {on|off|status|help}
lidrun() {
  local cmd="${1:-help}"
  case "$cmd" in
    on)
      if [[ "$OSTYPE" == "darwin"* ]]; then
        _lidrun_on_macos
      else
        _lidrun_on_linux
      fi
      ;;
    off)
      if [[ "$OSTYPE" == "darwin"* ]]; then
        _lidrun_off_macos
      else
        _lidrun_off_linux
      fi
      ;;
    status) _lidrun_status ;;
    help)   _lidrun_help ;;
    *)      echo "Unknown command: $cmd"; _lidrun_help; return 1 ;;
  esac
}
