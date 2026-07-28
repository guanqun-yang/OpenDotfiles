# Terminal color theme switcher
# Usage: theme [list|set|help]

# ── Theme Registry ──────────────────────────────────────────────────
# Each theme: "name|description|bg|fg|cursor|color0-15 (16 ANSI colors)"
# Colors are hex (#RRGGBB). ANSI palette order: black, red, green, yellow,
# blue, magenta, cyan, white, then bright variants (8-15).

_THEME_REGISTRY=(
  "Default|Standard terminal (white bg, black text)|#FFFFFF|#000000|#000000|#000000|#990000|#00A600|#999900|#0000B2|#B200B2|#00A6B2|#BFBFBF|#666666|#E50000|#00D900|#E5E500|#0000FF|#E500E5|#00E5E5|#E5E5E5"
  "Ubuntu|Ubuntu terminal (dark aubergine bg)|#300A24|#EEEEEC|#EEEEEC|#3B3B3B|#CC0000|#4E9A06|#C4A000|#5A8FCC|#AD7FA8|#06989A|#D3D7CF|#6C6C6C|#EF2929|#8AE234|#FCE94F|#729FCF|#D0A0E0|#34E2E2|#EEEEEC"
  "Solarized Dark|Precision colors for machines and people|#002B36|#839496|#839496|#073642|#DC322F|#859900|#B58900|#268BD2|#D33682|#2AA198|#EEE8D5|#002B36|#CB4B16|#586E75|#657B83|#839496|#6C71C4|#93A1A1|#FDF6E3"
  "Solarized Light|Solarized with light background|#FDF6E3|#657B83|#657B83|#073642|#DC322F|#859900|#B58900|#268BD2|#D33682|#2AA198|#EEE8D5|#002B36|#CB4B16|#586E75|#657B83|#839496|#6C71C4|#93A1A1|#FDF6E3"
  "Dracula|Dark theme with vibrant colors|#282A36|#F8F8F2|#F8F8F2|#21222C|#FF5555|#50FA7B|#F1FA8C|#BD93F9|#FF79C6|#8BE9FD|#F8F8F2|#6272A4|#FF6E6E|#69FF94|#FFFFA5|#D6ACFF|#FF92DF|#A4FFFF|#FFFFFF"
  "Monokai|Classic dark theme from Sublime Text|#272822|#F8F8F2|#F8F8F2|#272822|#F92672|#A6E22E|#F4BF75|#66D9EF|#AE81FF|#A1EFE4|#F8F8F2|#75715E|#F92672|#A6E22E|#F4BF75|#66D9EF|#AE81FF|#A1EFE4|#F9F8F5"
  "Nord|Arctic, north-bluish color palette|#2E3440|#D8DEE9|#D8DEE9|#3B4252|#BF616A|#A3BE8C|#EBCB8B|#81A1C1|#B48EAD|#88C0D0|#E5E9F0|#4C566A|#BF616A|#A3BE8C|#EBCB8B|#81A1C1|#B48EAD|#8FBCBB|#ECEFF4"
  "Gruvbox Dark|Retro groove color scheme|#282828|#EBDBB2|#EBDBB2|#282828|#CC241D|#98971A|#D79921|#458588|#B16286|#689D6A|#A89984|#928374|#FB4934|#B8BB26|#FABD2F|#83A598|#D3869B|#8EC07C|#EBDBB2"
)

# ── Helpers ─────────────────────────────────────────────────────────

_theme_ensure_dependency() {
  local cmd="$1" package="$2"
  if ! command -v "$cmd" &> /dev/null; then
    echo "⚠️  '$cmd' is required but not found."
    local install_cmd=""
    if command -v brew &> /dev/null; then
      install_cmd="brew install $package"
    elif command -v apt-get &> /dev/null; then
      install_cmd="sudo apt-get update && sudo apt-get install -y $package"
    elif command -v pacman &> /dev/null; then
      install_cmd="sudo pacman -S $package"
    else
      echo "❌ Please install '$package' manually."
      return 1
    fi
    echo "   To install, run: $install_cmd"
    read -p "   Install now? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      eval "$install_cmd"
    else
      return 1
    fi
  fi
}

# Parse a theme entry: sets THEME_NAME, THEME_DESC, THEME_BG, THEME_FG,
# THEME_CURSOR, THEME_ANSI (array of 16 colors)
_theme_parse() {
  local entry="$1"
  THEME_NAME="${entry%%|*}"; entry="${entry#*|}"
  THEME_DESC="${entry%%|*}"; entry="${entry#*|}"
  THEME_BG="${entry%%|*}"; entry="${entry#*|}"
  THEME_FG="${entry%%|*}"; entry="${entry#*|}"
  THEME_CURSOR="${entry%%|*}"; entry="${entry#*|}"
  # Remaining are 16 ANSI colors separated by |
  THEME_ANSI=()
  while [[ -n "$entry" ]]; do
    THEME_ANSI+=("${entry%%|*}")
    [[ "$entry" == *"|"* ]] && entry="${entry#*|}" || break
  done
}

# Apply a theme to the current terminal using OSC escape sequences
_theme_apply_osc() {
  local bg="$1" fg="$2" cursor="$3"
  shift 3
  local ansi=("$@")

  # Set foreground, background, cursor
  printf '\033]10;%s\007' "$fg"
  printf '\033]11;%s\007' "$bg"
  printf '\033]12;%s\007' "$cursor"

  # Set ANSI palette (colors 0-15)
  local idx=0
  for color in "${ansi[@]}"; do
    [[ -n "$color" ]] && printf '\033]4;%d;%s\007' "$idx" "$color"
    idx=$((idx + 1))
  done
}

# Generate a color preview string for a theme entry (used by fzf preview)
_theme_preview_script() {
  cat << 'PREVIEW_EOF'
#!/usr/bin/env bash
entry="$1"
IFS='|' read -ra parts <<< "$entry"
name="${parts[0]}"
desc="${parts[1]}"
bg="${parts[2]}"
fg="${parts[3]}"

echo "$name"
echo "$desc"
echo ""

# Convert hex to 256-color approximation for preview
_hex_to_rgb() {
  local hex="${1#\#}"
  printf '%d %d %d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

# Show color blocks using truecolor escapes
echo "  Background: $bg  Foreground: $fg"
echo ""

# Show ANSI palette as colored blocks
labels=("Blk" "Red" "Grn" "Ylw" "Blu" "Mag" "Cyn" "Wht")
echo "  Normal colors:"
line="  "
for i in {0..7}; do
  c="${parts[$((i+5))]}"
  if [[ -n "$c" ]]; then
    hex="${c#\#}"
    r=$((16#${hex:0:2})) g=$((16#${hex:2:2})) b=$((16#${hex:4:2}))
    line+="\033[48;2;${r};${g};${b}m   \033[0m "
  fi
done
echo -e "$line"

echo "  Bright colors:"
line="  "
for i in {8..15}; do
  c="${parts[$((i+5))]}"
  if [[ -n "$c" ]]; then
    hex="${c#\#}"
    r=$((16#${hex:0:2})) g=$((16#${hex:2:2})) b=$((16#${hex:4:2}))
    line+="\033[48;2;${r};${g};${b}m   \033[0m "
  fi
done
echo -e "$line"

echo ""
echo "  Sample text on background:"
bg_hex="${bg#\#}"
fg_hex="${fg#\#}"
br=$((16#${bg_hex:0:2})) bg_g=$((16#${bg_hex:2:2})) bb=$((16#${bg_hex:4:2}))
fr=$((16#${fg_hex:0:2})) fg_g=$((16#${fg_hex:2:2})) fb=$((16#${fg_hex:4:2}))
echo -e "  \033[48;2;${br};${bg_g};${bb}m\033[38;2;${fr};${fg_g};${fb}m  user@host:~\$ ls -la  \033[0m"
PREVIEW_EOF
}

# ── Subcommands ─────────────────────────────────────────────────────

_theme_search() {
  _theme_ensure_dependency "fzf" "fzf" || return 1

  # Build fzf input: "display_name\tfull_entry"
  local fzf_input=""
  for entry in "${_THEME_REGISTRY[@]}"; do
    _theme_parse "$entry"
    if [[ -n "$fzf_input" ]]; then
      fzf_input+=$'\n'
    fi
    fzf_input+="${THEME_NAME}\t${entry}"
  done

  # Create temporary preview script
  local preview_script=$(mktemp /tmp/theme_preview.XXXXXX)
  _theme_preview_script > "$preview_script"
  chmod +x "$preview_script"

  local selection
  selection=$(printf '%b' "$fzf_input" | \
    fzf --delimiter='\t' --with-nth=1 \
        --height=60% --layout=reverse --border \
        --header="Select Theme (Enter to apply)" \
        --preview="bash $preview_script {2}" \
        --preview-window=right:45%:wrap \
        --color=header:italic:underline)

  rm -f "$preview_script"

  if [[ -n "$selection" ]]; then
    local entry=$(echo "$selection" | cut -f2-)
    _theme_parse "$entry"
    _theme_apply_osc "$THEME_BG" "$THEME_FG" "$THEME_CURSOR" "${THEME_ANSI[@]}"
    echo "✅ Applied: $THEME_NAME"
  fi
}

_theme_list() {
  for entry in "${_THEME_REGISTRY[@]}"; do
    _theme_parse "$entry"
    printf "  %-20s %s\n" "$THEME_NAME" "$THEME_DESC"
  done
}

_theme_set() {
  local target="$1"
  if [[ -z "$target" ]]; then
    echo "Usage: theme set <name>"
    echo "Available themes:"
    _theme_list
    return 1
  fi

  # Find theme by name (case-insensitive)
  local found="" _tname _ttarget
  for entry in "${_THEME_REGISTRY[@]}"; do
    _theme_parse "$entry"
    if [[ -n "$ZSH_VERSION" ]]; then
      _tname="${THEME_NAME:l}"
      _ttarget="${target:l}"
    else
      _tname="${THEME_NAME,,}"
      _ttarget="${target,,}"
    fi
    if [[ "$_tname" == "$_ttarget" ]]; then
      found="$entry"
      break
    fi
  done

  if [[ -z "$found" ]]; then
    echo "❌ Theme '$target' not found."
    _theme_list
    return 1
  fi

  _theme_parse "$found"

  # Apply immediately
  _theme_apply_osc "$THEME_BG" "$THEME_FG" "$THEME_CURSOR" "${THEME_ANSI[@]}"

  # Persist based on terminal
  if [[ "$TERM_PROGRAM" == "Apple_Terminal" ]]; then
    # Map theme name to Terminal.app profile if it's Default
    if [[ "$THEME_NAME" == "Default" ]]; then
      defaults write com.apple.Terminal "Default Window Settings" -string "Basic"
      defaults write com.apple.Terminal "Startup Window Settings" -string "Basic"
      echo "✅ Applied & persisted: $THEME_NAME (Terminal.app → Basic profile)"
    else
      echo "✅ Applied: $THEME_NAME (session only — Terminal.app persistence requires a matching profile)"
      echo "   Tip: Save current settings as a profile in Terminal → Preferences → Profiles"
    fi
  elif [[ "$TERM_PROGRAM" == "iTerm.app" ]]; then
    echo "✅ Applied: $THEME_NAME (session only — use iTerm2 Preferences to persist)"
  elif [[ -n "$GNOME_TERMINAL_SCREEN" ]]; then
    local profile_id=$(dconf read /org/gnome/terminal/legacy/profiles:/default 2>/dev/null | tr -d "'")
    if [[ -n "$profile_id" ]]; then
      dconf write "/org/gnome/terminal/legacy/profiles:/:${profile_id}/background-color" "'${THEME_BG}'"
      dconf write "/org/gnome/terminal/legacy/profiles:/:${profile_id}/foreground-color" "'${THEME_FG}'"
      dconf write "/org/gnome/terminal/legacy/profiles:/:${profile_id}/use-theme-colors" "false"
      echo "✅ Applied & persisted: $THEME_NAME (GNOME Terminal)"
    else
      echo "✅ Applied: $THEME_NAME (could not detect GNOME Terminal profile for persistence)"
    fi
  else
    echo "✅ Applied: $THEME_NAME (session only — persist manually in your terminal settings)"
  fi
}

_theme_help() {
  echo "Usage: theme [command]"
  echo ""
  echo "Commands:"
  echo "  (none)      Interactive theme picker with preview"
  echo "  set <name>  Apply theme and persist as default"
  echo "  list        List available themes"
  echo "  help        Show this help message"
}

# Switch terminal color themes: theme [set <name>|list|help]
theme() {
  case "$1" in
    set)    shift; _theme_set "$@" ;;
    list)   _theme_list ;;
    help)   _theme_help ;;
    *)      _theme_search ;;
  esac
}
