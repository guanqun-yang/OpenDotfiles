# Parse commands from dotfiles .sh files (helper for list_cmds)
_parse_cmds() {
    local dir="$HOME/dotfiles"
    for file in "$dir"/core/*.sh "$dir"/macos/*.sh; do
        [ -e "$file" ] || continue
        local filename=$(basename "$file")
        local subdir=$(basename "$(dirname "$file")")
        local tag=""
        [[ "$subdir" == "macos" ]] && tag="[macos] "
        awk -v fname="$filename" -v tag="$tag" '
            /^#/ {
                sub(/^# ?/, "", $0)
                if (doc == "") doc = $0
                else doc = doc " " $0
                next
            }
            /^[a-zA-Z0-9_-]+\(\) *\{/ {
                cmd = $1; sub(/\(\).*/, "", cmd)
                if (cmd !~ /^_/) printf "%s\t%s\t%s%s\n", fname, cmd, tag, doc
                doc = ""; next
            }
            /^function [a-zA-Z0-9_-]+/ {
                cmd = $2; sub(/\(\)/, "", cmd)
                if (cmd !~ /^_/) printf "%s\t%s\t%s%s\n", fname, cmd, tag, doc
                doc = ""; next
            }
            !/^[ \t]*$/ { doc = "" }
        ' "$file"
    done
}

# Fuzzy search custom commands with descriptions in preview
list_cmds() {
    if ! command -v fzf &> /dev/null; then
        echo "⚠️  fzf is required. Install with: brew install fzf"
        return 1
    fi

    # Format: command\tdescription\tsource_file
    local selection=$(_parse_cmds | awk -F'\t' '{printf "%s\t%s\t%s\n", $2, $3, $1}' | \
        fzf --delimiter='\t' --with-nth=1 \
            --height=40% --layout=reverse --border \
            --header="Search commands (preview shows description)" \
            --preview='echo -e "Description:\n  {2}\n\nSource: {3}"' \
            --preview-window=down:5:wrap)

    if [[ -n "$selection" ]]; then
        local cmd=$(echo "$selection" | awk -F'\t' '{print $1}')
        echo "$cmd"
    fi
}
