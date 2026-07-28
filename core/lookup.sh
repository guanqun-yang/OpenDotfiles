# Open a URL template with a search term plugged in
_lookup_search() {
  _ensure_dependency "jq" "jq" || return 1
  _ensure_dependency "fzf" "fzf" || return 1

  local json_file="$HOME/dotfiles/data/lookups.json"

  if [[ ! -f "$json_file" ]]; then
    echo "Error: Lookup templates not found at $json_file"
    return 1
  fi

  local term="$1"
  if [[ -z "$term" ]]; then
    echo -n "Search term: "; read -r term
    [[ -z "$term" ]] && { echo "❌ No search term provided."; return 1; }
  fi

  local selection=$(jq -r '.[] | "\(.desc)\t\(.url)"' "$json_file" | \
    fzf --delimiter='\t' --with-nth=1 \
        --height=50% --layout=reverse --border \
        --header="Select template for: $term" \
        --preview="echo {2} | sed 's/{}/$term/g'" \
        --preview-window=down:3:wrap \
        --color=header:italic:underline)

  if [[ -n "$selection" ]]; then
    local url_template=$(echo "$selection" | cut -f2)
    local encoded=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$term" 2>/dev/null || echo "$term")
    local url="${url_template//\{\}/$encoded}"

    echo "🔗 $url"
    if [[ "$OSTYPE" == "darwin"* ]]; then
      open "$url"
    elif command -v xdg-open > /dev/null; then
      xdg-open "$url"
    else
      echo "Open the URL above in your browser."
    fi
  fi
}

# Add a new lookup URL template
_lookup_add() {
  _ensure_dependency "jq" "jq" || return 1

  local json_file="$HOME/dotfiles/data/lookups.json"
  [[ ! -f "$json_file" ]] && echo "[]" > "$json_file"

  echo -n "Description: "; read -r desc
  [[ -z "$desc" ]] && { echo "❌ Cancelled."; return 1; }

  echo -n "URL template (use {} for search term): "; read -r url
  [[ -z "$url" ]] && { echo "❌ Cancelled."; return 1; }

  local tmp=$(mktemp)
  jq --arg desc "$desc" --arg url "$url" \
    '. += [{"desc": $desc, "url": $url}]' "$json_file" > "$tmp" && mv "$tmp" "$json_file"

  echo "✅ Added: $desc"
}

# Delete a lookup URL template
_lookup_delete() {
  _ensure_dependency "jq" "jq" || return 1
  _ensure_dependency "fzf" "fzf" || return 1

  local json_file="$HOME/dotfiles/data/lookups.json"

  local selection=$(jq -r 'to_entries[] | "\(.key)\t\(.value.desc)\t\(.value.url)"' "$json_file" | \
    fzf --delimiter='\t' --with-nth=2 \
        --height=50% --layout=reverse --border \
        --header="Select template to DELETE" \
        --preview='echo {3}' \
        --preview-window=down:3:wrap)

  [[ -z "$selection" ]] && { echo "❌ Cancelled."; return 1; }

  local idx=$(echo "$selection" | cut -f1)
  local desc=$(echo "$selection" | cut -f2)

  echo -n "⚠️  Delete \"$desc\"? (y/N) "; read -k 1 -r REPLY
  echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && { echo "❌ Cancelled."; return 1; }

  local tmp=$(mktemp)
  jq --argjson idx "$idx" 'del(.[$idx])' "$json_file" > "$tmp" && mv "$tmp" "$json_file"

  echo "✅ Deleted: $desc"
}

# List all lookup templates
_lookup_list() {
  _ensure_dependency "jq" "jq" || return 1

  local json_file="$HOME/dotfiles/data/lookups.json"

  if [[ ! -f "$json_file" ]]; then
    echo "Error: Lookup templates not found at $json_file"
    return 1
  fi

  jq -r '.[] | "[\(.desc)] \(.url)"' "$json_file"
}

# Show help
_lookup_help() {
  echo "Usage: lookup [command] [term]"
  echo ""
  echo "Commands:"
  echo "  (none)    Enter a search term, then pick a URL template to open"
  echo "  add       Add a new URL template"
  echo "  delete    Delete a URL template"
  echo "  list      List all URL templates"
  echo "  help      Show this help message"
  echo ""
  echo "URL templates use {} as placeholder for the search term."
  echo "Example: lookup DTCR"
}

# Open a search term in a URL template: lookup {add|delete|list|help|<term>}
lookup() {
  case "$1" in
    add)    _lookup_add ;;
    delete) _lookup_delete ;;
    list)   _lookup_list ;;
    help)   _lookup_help ;;
    *)      _lookup_search "$1" ;;
  esac
}
