# Fuzzy search and copy frequently used configs stored in dotfiles/data/configs.json
cfg() {
  # 1. Dependency Checks (reuse helper from prompt.sh)
  _ensure_dependency "jq" "jq" || return 1
  _ensure_dependency "fzf" "fzf" || return 1

  # 2. Locate Data File
  local json_file="$HOME/dotfiles/data/configs.json"

  if [[ ! -f "$json_file" ]]; then
    echo "Error: Config library not found at $json_file"
    return 1
  fi

  # 3. Build selection list (index + description)
  local selection=$(jq -r 'to_entries[] | "\(.key)\t\(.value.desc)"' "$json_file" | \
    fzf --delimiter='\t' --with-nth=2 \
        --height=40% --layout=reverse --border \
        --header="Select Config (Enter to copy)" \
        --color=header:italic:underline)

  if [[ -n "$selection" ]]; then
    local index=$(echo "$selection" | awk -F'\t' '{print $1}')
    local config=$(jq ".[$index].config" "$json_file")

    # Platform-agnostic clipboard
    if [[ "$OSTYPE" == "darwin"* ]]; then
      echo -n "$config" | pbcopy
    elif command -v wl-copy > /dev/null; then
      echo -n "$config" | wl-copy
    elif command -v xclip > /dev/null; then
      echo -n "$config" | xclip -selection clipboard
    else
      echo "No clipboard tool found (pbcopy/wl-copy/xclip)."
      echo "   Here is your config:"
    fi

    echo "Copied to clipboard!"
    echo "$config"
  fi
}
