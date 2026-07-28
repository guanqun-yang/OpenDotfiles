_ensure_dependency() {
  local cmd="$1"
  local package="$2"

  if ! command -v "$cmd" &> /dev/null; then
    echo "⚠️  Command '$cmd' is required but not found."

    local install_cmd=""
    if command -v brew &> /dev/null; then
      install_cmd="brew install $package"
    elif command -v apt-get &> /dev/null; then
      install_cmd="sudo apt-get update && sudo apt-get install -y $package"
    elif command -v pacman &> /dev/null; then
      install_cmd="sudo pacman -S $package"
    else
      echo "❌ Could not detect a supported package manager (brew/apt/pacman)."
      echo "   Please install '$package' manually."
      return 1
    fi

    echo "   To install, run: $install_cmd"
    read -p "   Do you want to install '$package' now? (y/N) " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo "📦 Running: $install_cmd"
      eval "$install_cmd"
    else
      echo "❌ Dependency missing. Aborting."
      return 1
    fi
  fi
}

# Fuzzy search and copy frequently used prompts stored in dotfiles/data/prompts.json
_prompt_search() {
  _ensure_dependency "jq" "jq" || return 1
  _ensure_dependency "fzf" "fzf" || return 1

  local json_file="$HOME/dotfiles/data/prompts.json"

  if [[ ! -f "$json_file" ]]; then
    echo "Error: Prompt library not found at $json_file"
    return 1
  fi

  # Use base64 encoding to handle multi-line prompts
  local selection=$(jq -r '.[] | "\(.desc)\t\(.prompt | @base64)"' "$json_file" | \
    fzf --delimiter='\t' --with-nth=1 \
        --height=50% --layout=reverse --border \
        --header="Select Prompt (Enter to copy)" \
        --preview='echo {} | cut -f2 | base64 -d' \
        --preview-window=down:5:wrap \
        --color=header:italic:underline)

  if [[ -n "$selection" ]]; then
    local prompt_text=$(echo "$selection" | cut -f2 | base64 -d)

    # Platform-agnostic clipboard
    if [[ "$OSTYPE" == "darwin"* ]]; then
      echo -n "$prompt_text" | pbcopy
    elif command -v wl-copy > /dev/null; then
      echo -n "$prompt_text" | wl-copy
    elif command -v xclip > /dev/null; then
      echo -n "$prompt_text" | xclip -selection clipboard
    else
      echo "⚠️  No clipboard tool found (pbcopy/wl-copy/xclip)."
      echo "   Here is your prompt:"
      echo "$prompt_text"
      return 0
    fi

    echo "✅ Copied to clipboard!"
    echo "$prompt_text"
  fi
}

# Helper: Open editor with template, return parsed desc and prompt content
_prompt_edit_entry() {
  local initial_desc="$1"
  local initial_prompt="$2"
  local tmpfile=$(mktemp /tmp/prompt_edit.XXXXXX)

  cat > "$tmpfile" << EOF
# ┌─────────────────────────────────────────────────────────────┐
# │  Prompt Entry Editor                                        │
# │  • Edit the content below the headers                       │
# │  • Lines starting with # are ignored in the title section   │
# │  • Save and quit (:wq) to confirm, quit without saving to   │
# │    cancel                                                    │
# └─────────────────────────────────────────────────────────────┘

# TITLE (edit the line below):
$initial_desc

# PROMPT CONTENT (everything below this line until end of file):
$initial_prompt
EOF

  local checksum_before=$(md5sum "$tmpfile" 2>/dev/null || md5 -q "$tmpfile")
  ${EDITOR:-vim} "$tmpfile"
  local checksum_after=$(md5sum "$tmpfile" 2>/dev/null || md5 -q "$tmpfile")

  if [[ "$checksum_before" == "$checksum_after" ]]; then
    rm "$tmpfile"
    echo "CANCELLED"
    return 1
  fi

  # Parse: title is first non-comment non-empty line after TITLE header
  # Content is everything after PROMPT CONTENT header (preserving all lines)
  local desc="" content="" in_title=0 in_content=0
  while IFS= read -r line; do
    if [[ "$line" == "# TITLE (edit the line below):" ]]; then
      in_title=1; in_content=0; continue
    fi
    if [[ "$line" == "# PROMPT CONTENT (everything below this line until end of file):" ]]; then
      in_title=0; in_content=1; continue
    fi

    if [[ $in_title -eq 1 ]]; then
      [[ "$line" =~ ^# ]] && continue
      [[ -z "$line" ]] && continue
      [[ -z "$desc" ]] && desc="$line"
    elif [[ $in_content -eq 1 ]]; then
      # Append all lines (including blank and # lines) to content
      if [[ -z "$content" ]]; then
        content="$line"
      else
        content="$content
$line"
      fi
    fi
  done < "$tmpfile"

  rm "$tmpfile"

  # Trim leading/trailing blank lines from content
  content=$(printf '%s\n' "$content" | awk '
    { lines[NR] = $0 }
    /[^[:space:]]/ { last = NR; if (!first) first = NR }
    END { for (i = first; i <= last; i++) print lines[i] }
  ')

  if [[ -z "$desc" || -z "$content" ]]; then
    echo "Error: Both title and content are required."
    return 1
  fi

  # Return via global vars
  PROMPT_DESC="$desc"
  PROMPT_CONTENT="$content"
}

# Add a new prompt entry
_prompt_add() {
  _ensure_dependency "jq" "jq" || return 1

  local json_file="$HOME/dotfiles/data/prompts.json"

  if [[ ! -f "$json_file" ]]; then
    echo "[]" > "$json_file"
  fi

  if ! _prompt_edit_entry "" ""; then
    echo "❌ Cancelled."
    return 1
  fi

  # Append to JSON array
  local tmp=$(mktemp)
  jq --arg desc "$PROMPT_DESC" --arg prompt "$PROMPT_CONTENT" \
    '. += [{"desc": $desc, "prompt": $prompt}]' "$json_file" > "$tmp" && mv "$tmp" "$json_file"

  echo "✅ Added: $PROMPT_DESC"
}

# Edit an existing prompt entry
_prompt_edit() {
  _ensure_dependency "jq" "jq" || return 1
  _ensure_dependency "fzf" "fzf" || return 1

  local json_file="$HOME/dotfiles/data/prompts.json"

  # Select entry with fzf (show index for identification)
  local selection=$(jq -r 'to_entries[] | "\(.key)\t\(.value.desc)\t\(.value.prompt | @base64)"' "$json_file" | \
    fzf --delimiter='\t' --with-nth=2 \
        --height=50% --layout=reverse --border \
        --header="Select prompt to edit" \
        --preview='echo {3} | base64 -d' \
        --preview-window=down:5:wrap)

  [[ -z "$selection" ]] && { echo "❌ Cancelled."; return 1; }

  local idx=$(echo "$selection" | cut -f1)
  local old_desc=$(echo "$selection" | cut -f2)
  local old_prompt=$(echo "$selection" | cut -f3 | base64 -d)

  if ! _prompt_edit_entry "$old_desc" "$old_prompt"; then
    echo "❌ Cancelled."
    return 1
  fi

  # Update JSON at index
  local tmp=$(mktemp)
  jq --argjson idx "$idx" --arg desc "$PROMPT_DESC" --arg prompt "$PROMPT_CONTENT" \
    '.[$idx] = {"desc": $desc, "prompt": $prompt}' "$json_file" > "$tmp" && mv "$tmp" "$json_file"

  echo "✅ Updated: $PROMPT_DESC"
}

# Delete a prompt entry
_prompt_delete() {
  _ensure_dependency "jq" "jq" || return 1
  _ensure_dependency "fzf" "fzf" || return 1

  local json_file="$HOME/dotfiles/data/prompts.json"

  local selection=$(jq -r 'to_entries[] | "\(.key)\t\(.value.desc)\t\(.value.prompt | @base64)"' "$json_file" | \
    fzf --delimiter='\t' --with-nth=2 \
        --height=50% --layout=reverse --border \
        --header="Select prompt to DELETE" \
        --preview='echo {3} | base64 -d' \
        --preview-window=down:5:wrap)

  [[ -z "$selection" ]] && { echo "❌ Cancelled."; return 1; }

  local idx=$(echo "$selection" | cut -f1)
  local desc=$(echo "$selection" | cut -f2)

  read -p "⚠️  Delete \"$desc\"? (y/N) " -n 1 -r
  echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && { echo "❌ Cancelled."; return 1; }

  local tmp=$(mktemp)
  jq --argjson idx "$idx" 'del(.[$idx])' "$json_file" > "$tmp" && mv "$tmp" "$json_file"

  echo "✅ Deleted: $desc"
}

# List all prompts
_prompt_list() {
  _ensure_dependency "jq" "jq" || return 1

  local json_file="$HOME/dotfiles/data/prompts.json"

  if [[ ! -f "$json_file" ]]; then
    echo "Error: Prompt library not found at $json_file"
    return 1
  fi

  jq -r '.[] | "[\(.desc)]"' "$json_file"
}

# Show available subcommands
_prompt_help() {
  echo "Usage: prompt [command]"
  echo ""
  echo "Commands:"
  echo "  (none)    Fuzzy search prompts and copy to clipboard"
  echo "  add       Add a new prompt"
  echo "  edit      Edit an existing prompt"
  echo "  delete    Delete a prompt"
  echo "  list      List all prompt titles"
  echo "  help      Show this help message"
}

# Manage prompt snippets: prompt {add|edit|delete|list|help} or fuzzy search
prompt() {
  case "$1" in
    add)    _prompt_add ;;
    edit)   _prompt_edit ;;
    delete) _prompt_delete ;;
    list)   _prompt_list ;;
    help)   _prompt_help ;;
    *)      _prompt_search ;;
  esac
}
