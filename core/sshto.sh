# ── SSH Theme Helpers ──────────────────────────────────────────────

_SSHTO_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/sshto"

# Reset terminal palette to Default on new shell startup.
# This fixes Ctrl+T (new tab) inheriting SSH session theme colors.
if [[ -f "$_SSHTO_STATE_DIR/theme_active" ]]; then
  _theme_apply_osc_default() {
    # Inline Default palette reset (avoids dependency on _theme_set at source time)
    printf '\033]10;%s\007' "#000000"
    printf '\033]11;%s\007' "#FFFFFF"
    printf '\033]12;%s\007' "#000000"
    local i=0 c
    for c in "#000000" "#990000" "#00A600" "#999900" "#0000B2" "#B200B2" "#00A6B2" "#BFBFBF" "#666666" "#E50000" "#00D900" "#E5E500" "#0000FF" "#E500E5" "#00E5E5" "#E5E5E5"; do
      printf '\033]4;%d;%s\007' "$i" "$c"
      i=$((i + 1))
    done
  }
  _theme_apply_osc_default
  unfunction _theme_apply_osc_default 2>/dev/null
  rm -f "$_SSHTO_STATE_DIR/theme_active"
fi

# Get the theme assigned to a host, or empty string
_sshto_get_theme() {
  local host="$1"
  local map_file="$_SSHTO_STATE_DIR/host_themes"
  [[ -f "$map_file" ]] || return
  grep "^${host}	" "$map_file" 2>/dev/null | cut -f2
}

# Get all themes currently assigned to hosts
_sshto_used_themes() {
  local map_file="$_SSHTO_STATE_DIR/host_themes"
  [[ -f "$map_file" ]] || return
  cut -f2 "$map_file" 2>/dev/null
}

# Assign a theme to a host (append to map file)
_sshto_assign_theme() {
  local host="$1" theme="$2"
  mkdir -p "$_SSHTO_STATE_DIR"
  printf '%s\t%s\n' "$host" "$theme" >> "$_SSHTO_STATE_DIR/host_themes"
}

# Pick the next available theme for a host (skips Default and already-used themes)
_sshto_pick_theme() {
  local used
  used=$(_sshto_used_themes)
  for entry in "${_THEME_REGISTRY[@]}"; do
    _theme_parse "$entry"
    [[ "$THEME_NAME" == "Default" ]] && continue
    if ! echo "$used" | grep -qxF "$THEME_NAME"; then
      echo "$THEME_NAME"
      return
    fi
  done
  # All themes used — cycle back to first non-Default
  for entry in "${_THEME_REGISTRY[@]}"; do
    _theme_parse "$entry"
    [[ "$THEME_NAME" != "Default" ]] && echo "$THEME_NAME" && return
  done
}

# Extract hostname from an ssh command like "ssh user@host" or "ssh host"
_sshto_extract_host() {
  local cmd="$1"
  # Grab the last argument (user@host or host), strip user@ prefix
  local target="${cmd##* }"
  echo "${target##*@}"
}

# ── Main ──────────────────────────────────────────────────────────

# Fuzzy search and connect to SSH locations stored in dotfiles/data/ssh.json
sshto() {
  # 1. Dependency Checks (reuse helper from prompt.sh)
  _ensure_dependency "jq" "jq" || return 1
  _ensure_dependency "fzf" "fzf" || return 1

  # 2. Locate Data File
  local json_file="$HOME/dotfiles/data/ssh.json"

  if [[ ! -f "$json_file" ]]; then
    echo "Error: SSH config not found at $json_file"
    return 1
  fi

  # 3. Build selection list (desc + cmd)
  local selection=$(jq -r '.[] | "\(.desc)\t\(.cmd)"' "$json_file" | \
    fzf --delimiter='\t' --with-nth=1 \
        --height=40% --layout=reverse --border \
        --header="Select SSH destination (Enter to connect)" \
        --color=header:italic:underline)

  if [[ -n "$selection" ]]; then
    local cmd=$(echo "$selection" | awk -F'\t' '{print $2}')
    local host=$(_sshto_extract_host "$cmd")

    # 4. Resolve or assign a theme for this host
    local theme_name
    theme_name=$(_sshto_get_theme "$host")
    if [[ -z "$theme_name" ]]; then
      theme_name=$(_sshto_pick_theme)
      _sshto_assign_theme "$host" "$theme_name"
    fi

    # 5. Apply remote theme
    if [[ -n "$theme_name" ]]; then
      _theme_set "$theme_name" 2>/dev/null
      mkdir -p "$_SSHTO_STATE_DIR"
      touch "$_SSHTO_STATE_DIR/theme_active"
      echo "Theme '$theme_name' applied for host '$host'"
    fi

    # 6. Connect
    echo "Connecting: $cmd"
    eval "$cmd"

    # 7. Restore default theme on disconnect
    _theme_set "Default" 2>/dev/null
    rm -f "$_SSHTO_STATE_DIR/theme_active"
    echo "Theme restored to Default"
  fi
}
