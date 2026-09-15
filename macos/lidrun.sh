# Clamshell / lid-close helper
# Keeps the MacBook awake with the lid closed via pmset disablesleep.

_LIDRUN_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/lidrun"

_lidrun_save() { local k="$1" v="$2"; mkdir -p "$_LIDRUN_STATE_DIR"; printf '%s' "$v" > "$_LIDRUN_STATE_DIR/$k"; }
_lidrun_load() { local f="$_LIDRUN_STATE_DIR/$1"; [[ -f "$f" ]] && cat "$f"; }

_lidrun_sleep_disabled() {
  pmset -g | awk '/SleepDisabled/ {print $2}'
}

_lidrun_on() {
  echo "Disabling sleep on lid close (requires sudo)..."
  sudo pmset -a disablesleep 1
  if [[ "$(_lidrun_sleep_disabled)" != "1" ]]; then
    echo "  Failed: pmset still reports SleepDisabled=$(_lidrun_sleep_disabled)"
    return 1
  fi
  echo "  Lid sleep: disabled"

  _lidrun_save "active" "1"
  echo "Clamshell mode ON. Safe to close the lid."
  echo "Note: this setting persists across reboots; run 'lidrun off' when done."
}

_lidrun_off() {
  echo "Re-enabling sleep on lid close (requires sudo)..."
  sudo pmset -a disablesleep 0
  echo "  Lid sleep: enabled"

  _lidrun_save "active" "0"
  echo "Clamshell mode OFF. Normal lid behavior restored."
}

_lidrun_status() {
  local active
  active=$(_lidrun_load "active")
  if [[ "$active" == "1" ]]; then
    echo "Clamshell mode: ON"
  else
    echo "Clamshell mode: OFF"
  fi
  echo "  SleepDisabled: $(_lidrun_sleep_disabled)"
}

_lidrun_help() {
  echo "Usage: lidrun <command>"
  echo ""
  echo "Keep the MacBook running with the lid closed (clamshell mode)."
  echo ""
  echo "Commands:"
  echo "  on      Disable sleep on lid close (sudo pmset -a disablesleep 1)"
  echo "  off     Restore normal lid behavior (sudo pmset -a disablesleep 0)"
  echo "  status  Show current state"
  echo "  help    Show this help message"
  echo ""
  echo "Note: the pmset flag persists across reboots; run 'lidrun off' when done."
}

# Run laptop with lid closed: lidrun {on|off|status|help}
lidrun() {
  local cmd="${1:-help}"
  case "$cmd" in
    on)     _lidrun_on ;;
    off)    _lidrun_off ;;
    status) _lidrun_status ;;
    help)   _lidrun_help ;;
    *)      echo "Unknown command: $cmd"; _lidrun_help; return 1 ;;
  esac
}
