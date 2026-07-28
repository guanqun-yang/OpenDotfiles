_ems_ensure_dependency() {
  local cmd="$1"
  local package="$2"

  if ! command -v "$cmd" &> /dev/null; then
    echo "Warning: Command '$cmd' is required but not found."

    local install_cmd=""
    if command -v brew &> /dev/null; then
      install_cmd="brew install $package"
    elif command -v apt-get &> /dev/null; then
      install_cmd="sudo apt-get update && sudo apt-get install -y $package"
    elif command -v pacman &> /dev/null; then
      install_cmd="sudo pacman -S $package"
    else
      echo "Could not detect a supported package manager (brew/apt/pacman)."
      echo "   Please install '$package' manually."
      return 1
    fi

    echo "   To install, run: $install_cmd"
    read -p "   Do you want to install '$package' now? (y/N) " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo "Running: $install_cmd"
      eval "$install_cmd"
    else
      echo "Dependency missing. Aborting."
      return 1
    fi
  fi
}

# Directory where experience files live
EMS_DIR="${EMS_DIR:-$HOME/Resume/experiences}"

# Fuzzy search experiences and open in Typora
_ems_search() {
  _ems_ensure_dependency "fzf" "fzf" || return 1

  local files=("$EMS_DIR"/*.md)
  # Exclude README.md
  files=("${(@)files:#*README.md}")

  if [[ ${#files[@]} -eq 0 || ! -f "${files[1]}" ]]; then
    echo "No experience files found in $EMS_DIR"
    return 1
  fi

  local selection=$(for f in "${files[@]}"; do
    local basename=$(basename "$f" .md)
    local title=$(sed -n 's/^title: *"\(.*\)"/\1/p' "$f" | head -1)
    local status=$(sed -n 's/^status: *"\(.*\)"/\1/p' "$f" | head -1)
    local tags=$(sed -n 's/^tags: *\[\(.*\)\]/\1/p' "$f" | head -1 | tr -d '"')
    printf "%s\t%s\t[%s] %s\n" "$f" "$basename" "${status:-?}" "${title:-$basename}"
  done | fzf --delimiter='\t' --with-nth=3 \
      --height=50% --layout=reverse --border \
      --header="Select Experience (Enter to open in Typora)" \
      --preview='cat {1}' \
      --preview-window=right:60%:wrap \
      --color=header:italic:underline)

  if [[ -n "$selection" ]]; then
    local filepath=$(echo "$selection" | cut -f1)
    echo "Opening in Typora: $(basename "$filepath")"
    typora "$filepath" &
  fi
}

# Add a new experience file
_ems_add() {
  local now_yyyy=$(date +%Y)
  local now_mm=$(date +%m)

  read -p "Topic slug (e.g. podcast2pdf): " slug
  [[ -z "$slug" ]] && { echo "Cancelled."; return 1; }

  # Sanitize slug: lowercase, hyphens only
  slug=$(echo "$slug" | tr '[:upper:]' '[:lower:]' | tr ' _' '-' | tr -cd 'a-z0-9-')

  read -p "Date prefix [${now_yyyy}-${now_mm}]: " date_prefix
  date_prefix="${date_prefix:-${now_yyyy}-${now_mm}}"

  local filename="${date_prefix}-${slug}.md"
  local filepath="${EMS_DIR}/${filename}"

  if [[ -f "$filepath" ]]; then
    echo "File already exists: $filename"
    read -p "Open it in Typora? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      typora "$filepath" &
    fi
    return 0
  fi

  local timestamp=$(date +%Y-%m-%d-%H-%M-%S)

  cat > "$filepath" << 'TEMPLATE'
---
title: ""
role: ""
tags: []
status: "Active"
last_updated: TIMESTAMP_PLACEHOLDER
---

## Description


## Metrics


## Technical Details

TEMPLATE

  # Replace timestamp placeholder
  sed -i '' "s/TIMESTAMP_PLACEHOLDER/$timestamp/" "$filepath"

  echo "Created: $filename"
  typora "$filepath" &
}

# List all experience files with metadata
_ems_list() {
  local files=("$EMS_DIR"/*.md)
  files=("${(@)files:#*README.md}")

  if [[ ${#files[@]} -eq 0 || ! -f "${files[1]}" ]]; then
    echo "No experience files found in $EMS_DIR"
    return 1
  fi

  printf "%-28s %-10s %s\n" "FILE" "STATUS" "TITLE"
  printf "%-28s %-10s %s\n" "----" "------" "-----"

  for f in "${files[@]}"; do
    local basename=$(basename "$f" .md)
    local title=$(sed -n 's/^title: *"\(.*\)"/\1/p' "$f" | head -1)
    local status=$(sed -n 's/^status: *"\(.*\)"/\1/p' "$f" | head -1)
    printf "%-28s %-10s %s\n" "$basename" "${status:-?}" "${title:-$basename}"
  done
}

# Delete an experience file
_ems_delete() {
  _ems_ensure_dependency "fzf" "fzf" || return 1

  local files=("$EMS_DIR"/*.md)
  files=("${(@)files:#*README.md}")

  if [[ ${#files[@]} -eq 0 || ! -f "${files[1]}" ]]; then
    echo "No experience files found in $EMS_DIR"
    return 1
  fi

  local selection=$(for f in "${files[@]}"; do
    local basename=$(basename "$f" .md)
    local title=$(sed -n 's/^title: *"\(.*\)"/\1/p' "$f" | head -1)
    local status=$(sed -n 's/^status: *"\(.*\)"/\1/p' "$f" | head -1)
    printf "%s\t%s\t[%s] %s\n" "$f" "$basename" "${status:-?}" "${title:-$basename}"
  done | fzf --delimiter='\t' --with-nth=3 \
      --height=50% --layout=reverse --border \
      --header="Select Experience to DELETE" \
      --preview='cat {1}' \
      --preview-window=right:60%:wrap)

  [[ -z "$selection" ]] && { echo "Cancelled."; return 1; }

  local filepath=$(echo "$selection" | cut -f1)
  local basename=$(basename "$filepath")

  read -p "Delete \"$basename\"? (y/N) " -n 1 -r
  echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && { echo "Cancelled."; return 1; }

  rm "$filepath"
  echo "Deleted: $basename"
}

# Show available subcommands
_ems_help() {
  echo "Usage: ems [command]"
  echo ""
  echo "Experience Management System - manage experience files in $EMS_DIR"
  echo ""
  echo "Commands:"
  echo "  (none)    Fuzzy search experiences and open in Typora"
  echo "  add       Create a new experience file and open in Typora"
  echo "  list      List all experiences with status"
  echo "  delete    Delete an experience file"
  echo "  help      Show this help message"
  echo ""
  echo "Files follow the YYYY-MM-Topic.md naming convention."
  echo "Set EMS_DIR to override the default directory."
}

# Manage experience files: ems {add|list|delete|help} or fuzzy search
ems() {
  case "$1" in
    add)    _ems_add ;;
    list)   _ems_list ;;
    delete) _ems_delete ;;
    help)   _ems_help ;;
    *)      _ems_search ;;
  esac
}
