# Manage and sync reference material repos: ref [sync|add|edit|delete|list|help]
ref() {
  case "$1" in
    sync)   _ref_sync ;;
    add)    _ref_add ;;
    edit)   _ref_edit ;;
    delete) _ref_delete ;;
    list)   _ref_search ;;
    *)      _ref_help ;;
  esac
}

_ref_json() { echo "$HOME/dotfiles/data/refs.json"; }

_ref_ensure_dep() {
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

# Editor-based entry creation/editing (like _prompt_edit_entry)
_ref_edit_entry() {
  local initial_url="$1"
  local initial_dir="$2"
  local initial_desc="$3"
  local tmpfile=$(mktemp /tmp/ref_edit.XXXXXX)

  cat > "$tmpfile" << EOF
# ┌─────────────────────────────────────────────────────────────┐
# │  Reference Entry Editor                                      │
# │  • Edit the fields below                                     │
# │  • Lines starting with # are ignored                         │
# │  • Save and quit to confirm, quit without saving to cancel   │
# └─────────────────────────────────────────────────────────────┘

# GIT URL:
$initial_url

# TARGET DIR (folder name under ./resources/):
$initial_dir

# DESCRIPTION:
$initial_desc
EOF

  local checksum_before=$(md5sum "$tmpfile" 2>/dev/null || md5 -q "$tmpfile")
  ${EDITOR:-vim} "$tmpfile"
  local checksum_after=$(md5sum "$tmpfile" 2>/dev/null || md5 -q "$tmpfile")

  if [[ "$checksum_before" == "$checksum_after" ]]; then
    rm "$tmpfile"
    return 1
  fi

  # Parse fields: first non-comment non-empty line after each header
  local url="" dir="" desc="" section=""
  while IFS= read -r line; do
    case "$line" in
      "# GIT URL:")         section="url"; continue ;;
      "# TARGET DIR"*)      section="dir"; continue ;;
      "# DESCRIPTION:")     section="desc"; continue ;;
    esac
    [[ "$line" =~ ^# ]] && continue
    [[ -z "$line" ]] && continue

    case "$section" in
      url)  [[ -z "$url" ]]  && url="$line" ;;
      dir)  [[ -z "$dir" ]]  && dir="$line" ;;
      desc) [[ -z "$desc" ]] && desc="$line" ;;
    esac
  done < "$tmpfile"

  rm "$tmpfile"

  if [[ -z "$url" || -z "$dir" ]]; then
    echo "❌ URL and target dir are required."
    return 1
  fi

  REF_URL="$url"
  REF_DIR="$dir"
  REF_DESC="$desc"
}

# Fuzzy search refs (two columns: URL + dir) and cd into selected
_ref_search() {
  _ref_ensure_dep "jq" "jq" || return 1
  _ref_ensure_dep "fzf" "fzf" || return 1

  local json_file=$(_ref_json)
  [[ ! -f "$json_file" ]] && { echo "❌ $json_file not found."; return 1; }

  local resdir="$(pwd)/resources"

  local selection
  selection=$(jq -r '.[] | "\(.url)\t\(.dir)"' "$json_file" | \
    fzf --delimiter='\t' \
        --height=50% --layout=reverse --border \
        --header="Select ref (Enter to cd)" \
        --preview="dir=\"$resdir/\$(echo {} | cut -f2)\"; if [ -d \"\$dir\" ]; then echo \"\$dir\"; echo ''; ls -1 \"\$dir\" | head -30; else echo 'Not cloned yet. Run: ref sync'; fi" \
        --preview-window=right:40%:wrap \
        --color=header:italic:underline)

  if [[ -n "$selection" ]]; then
    local dir_name=$(echo "$selection" | cut -f2)
    local target="$resdir/$dir_name"
    if [[ -d "$target" ]]; then
      cd "$target" && echo "📂 $target"
    else
      echo "⚠️  '$dir_name' not cloned yet. Run: ref sync"
    fi
  fi
}

# Clone missing repos, pull existing ones into ./resources/
_ref_sync() {
  _ref_ensure_dep "jq" "jq" || return 1
  _ref_ensure_dep "git" "git" || return 1

  local json_file=$(_ref_json)
  [[ ! -f "$json_file" ]] && { echo "❌ $json_file not found."; return 1; }

  local resdir="$(pwd)/resources"
  mkdir -p "$resdir"

  local count=$(jq 'length' "$json_file")
  local i=0

  jq -r '.[] | "\(.url)\t\(.dir)"' "$json_file" | while IFS=$'\t' read -r url dir; do
    i=$((i + 1))
    local target="$resdir/$dir"

    if [[ -d "$target/.git" ]]; then
      echo "[$i/$count] Pulling $dir..."
      git -C "$target" pull --ff-only 2>&1 | sed 's/^/  /'
    else
      echo "[$i/$count] Cloning $dir..."
      git clone --depth 1 "$url" "$target" 2>&1 | sed 's/^/  /'
    fi
  done

  echo "✅ Sync complete. Resources in: $resdir"
}

# Add a new ref entry via editor
_ref_add() {
  _ref_ensure_dep "jq" "jq" || return 1

  local json_file=$(_ref_json)
  [[ ! -f "$json_file" ]] && echo "[]" > "$json_file"

  if ! _ref_edit_entry "" "" ""; then
    echo "❌ Cancelled."
    return 1
  fi

  # Check for duplicate dir
  if jq -e --arg d "$REF_DIR" '.[] | select(.dir == $d)' "$json_file" > /dev/null 2>&1; then
    echo "❌ Dir '$REF_DIR' already exists in refs."
    return 1
  fi

  local tmp=$(mktemp)
  jq --arg url "$REF_URL" --arg dir "$REF_DIR" --arg desc "$REF_DESC" \
    '. += [{"url": $url, "dir": $dir, "desc": $desc}]' "$json_file" > "$tmp" && mv "$tmp" "$json_file"

  echo "✅ Added: $REF_DIR ($REF_URL)"
}

# Edit an existing ref entry via fzf + editor
_ref_edit() {
  _ref_ensure_dep "jq" "jq" || return 1
  _ref_ensure_dep "fzf" "fzf" || return 1

  local json_file=$(_ref_json)

  local selection
  selection=$(jq -r 'to_entries[] | "\(.key)\t\(.value.url)\t\(.value.dir)\t\(.value.desc)"' "$json_file" | \
    fzf --delimiter='\t' --with-nth='2,3' \
        --height=50% --layout=reverse --border \
        --header="Select ref to edit" \
        --color=header:italic:underline)

  [[ -z "$selection" ]] && { echo "❌ Cancelled."; return 1; }

  local idx=$(echo "$selection" | cut -f1)
  local old_url=$(echo "$selection" | cut -f2)
  local old_dir=$(echo "$selection" | cut -f3)
  local old_desc=$(echo "$selection" | cut -f4)

  if ! _ref_edit_entry "$old_url" "$old_dir" "$old_desc"; then
    echo "❌ Cancelled."
    return 1
  fi

  local tmp=$(mktemp)
  jq --argjson idx "$idx" --arg url "$REF_URL" --arg dir "$REF_DIR" --arg desc "$REF_DESC" \
    '.[$idx] = {"url": $url, "dir": $dir, "desc": $desc}' "$json_file" > "$tmp" && mv "$tmp" "$json_file"

  echo "✅ Updated: $REF_DIR ($REF_URL)"
}

# Delete a ref entry via fzf (two columns: URL + dir)
_ref_delete() {
  _ref_ensure_dep "jq" "jq" || return 1
  _ref_ensure_dep "fzf" "fzf" || return 1

  local json_file=$(_ref_json)

  local selection
  selection=$(jq -r 'to_entries[] | "\(.key)\t\(.value.url)\t\(.value.dir)"' "$json_file" | \
    fzf --delimiter='\t' --with-nth='2,3' \
        --height=50% --layout=reverse --border \
        --header="Select ref to DELETE" \
        --color=header:italic:underline)

  [[ -z "$selection" ]] && { echo "❌ Cancelled."; return 1; }

  local idx=$(echo "$selection" | cut -f1)
  local dir=$(echo "$selection" | cut -f3)

  read -p "⚠️  Remove '$dir' from refs? (y/N) " -n 1 -r
  echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && { echo "❌ Cancelled."; return 1; }

  local tmp=$(mktemp)
  jq --argjson idx "$idx" 'del(.[$idx])' "$json_file" > "$tmp" && mv "$tmp" "$json_file"

  echo "✅ Removed from refs: $dir"

  # Optionally delete local clone
  local resdir="$(pwd)/resources"
  if [[ -d "$resdir/$dir" ]]; then
    read -p "   Also delete local clone at $resdir/$dir? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      rm -rf "$resdir/$dir"
      echo "   🗑️  Deleted $resdir/$dir"
    fi
  fi
}

# List all refs: two columns (URL + dir) with clone status
_ref_list() {
  _ref_ensure_dep "jq" "jq" || return 1

  local json_file=$(_ref_json)
  [[ ! -f "$json_file" ]] && { echo "❌ $json_file not found."; return 1; }

  local resdir="$(pwd)/resources"

  jq -r '.[] | "\(.url)\t\(.dir)"' "$json_file" | while IFS=$'\t' read -r url dir; do
    local marker="  "
    [[ -d "$resdir/$dir" ]] && marker="✓ "
    printf "  %s%-55s %s\n" "$marker" "$url" "$dir"
  done
}

_ref_help() {
  echo "Usage: ref [command]"
  echo ""
  echo "Commands:"
  echo "  list      Fuzzy search refs and cd into selected"
  echo "  sync      Clone missing repos, pull existing (into ./resources/)"
  echo "  add       Add a new reference repo"
  echo "  edit      Edit an existing reference repo"
  echo "  delete    Remove a reference repo"
  echo "  help      Show this help message"
  echo ""
  echo "Data: ~/dotfiles/data/refs.json"
}
