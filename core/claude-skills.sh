# Fetch Claude Skills from GitHub and install into current project's .claude/skills/
claude-skills() {
    local repo="https://github.com/guanqun-yang/OpenClaudeSkills.git"
    local cache_dir="$HOME/.cache/OpenClaudeSkills"
    local target_dir=".claude/skills"

    # Parse flags
    local force=false
    local list_only=false
    local mode=""
    local skills=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force) force=true; shift ;;
            -l|--list)  list_only=true; shift ;;
            -m|--mode)  mode="$2"; shift 2 ;;
            -h|--help)
                echo "Usage: claude-skills [options] [skill1 skill2 ...]"
                echo ""
                echo "Fetch Claude Skills from GitHub into .claude/skills/ of the current project,"
                echo "plus slash commands into .claude/commands/ and a CLAUDE.md based on use case (default: coding)."
                echo ""
                echo "Options:"
                echo "  -l, --list        List available skills, commands, and CLAUDE.md modes"
                echo "  -f, --force       Overwrite existing skills and CLAUDE.md"
                echo "  -m, --mode MODE   Set CLAUDE.md mode (skip fzf selector)"
                echo "  -h, --help        Show this help"
                echo ""
                echo "Examples:"
                echo "  claude-skills                # install all skills, pick CLAUDE.md via fzf"
                echo "  claude-skills -m coding      # install all skills, use coding CLAUDE.md"
                echo "  claude-skills -m blog system-branding  # specific mode + skill"
                echo "  claude-skills -l             # list available skills and modes"
                echo "  claude-skills -f             # force update everything"
                return 0
                ;;
            *) skills+=("$1"); shift ;;
        esac
    done

    # Always sync with the GitHub remote. Clone if missing, fast-forward pull if present.
    if [ ! -d "$cache_dir/.git" ]; then
        echo "Cloning skills repository to $cache_dir..."
        mkdir -p "$(dirname "$cache_dir")"
        git clone --quiet "$repo" "$cache_dir" || {
            echo "Error: clone failed."
            return 1
        }
    else
        echo "Syncing $repo..."
        local branch
        branch=$(git -C "$cache_dir" symbolic-ref --short HEAD 2>/dev/null || echo master)
        if git -C "$cache_dir" fetch --quiet origin "$branch" 2>/dev/null; then
            git -C "$cache_dir" reset --hard --quiet "origin/$branch"
        else
            echo "Warning: git fetch failed (offline). Using local $cache_dir as-is." >&2
        fi
    fi

    # Check that skills/ directory exists in the repo
    if [ ! -d "$cache_dir/skills" ]; then
        echo "Error: No skills/ directory found in repository."
        return 1
    fi

    # List mode
    if $list_only; then
        echo "Available skills:"
        for skill_dir in "$cache_dir"/skills/*/; do
            [ -d "$skill_dir" ] || continue
            local name=$(basename "$skill_dir")
            local desc=""
            if [ -f "$skill_dir/SKILL.md" ]; then
                desc=$(awk '/^description:/{sub(/^description: */, ""); print; exit}' "$skill_dir/SKILL.md")
            fi
            printf "  %-25s %s\n" "$name" "$desc"
        done
        echo ""
        echo "Available commands:"
        for cmd_file in "$cache_dir"/commands/*.md; do
            [ -f "$cmd_file" ] || continue
            local name=$(basename "$cmd_file" .md)
            local desc=$(awk '/^description:/{sub(/^description: */, ""); print; exit}' "$cmd_file")
            printf "  /%-24s %s\n" "$name" "$desc"
        done
        echo ""
        echo "Available CLAUDE.md modes:"
        for mode_dir in "$cache_dir"/claudemd/*/; do
            [ -d "$mode_dir" ] || continue
            local name=$(basename "$mode_dir")
            [ "$name" = "global" ] && continue
            local headline=$(head -1 "$mode_dir/CLAUDE.md" 2>/dev/null | sed 's/^# *//')
            printf "  %-25s %s\n" "$name" "$headline"
        done
        return 0
    fi

    # Determine which skills to install
    local available=()
    for skill_dir in "$cache_dir"/skills/*/; do
        [ -d "$skill_dir" ] || continue
        available+=($(basename "$skill_dir"))
    done

    if [ ${#available[@]} -eq 0 ]; then
        echo "No skills found in repository."
        return 1
    fi

    local to_install=()
    if [ ${#skills[@]} -eq 0 ]; then
        to_install=("${available[@]}")
    else
        for s in "${skills[@]}"; do
            local found=false
            for a in "${available[@]}"; do
                if [ "$s" = "$a" ]; then
                    found=true
                    break
                fi
            done
            if $found; then
                to_install+=("$s")
            else
                echo "Warning: skill '$s' not found. Available: ${available[*]}"
            fi
        done
    fi

    if [ ${#to_install[@]} -eq 0 ]; then
        echo "No skills to install."
        return 1
    fi

    # Install .claude/settings.json from the repo
    mkdir -p ".claude"
    local settings_src="$cache_dir/settings.json"
    if [ -f "$settings_src" ]; then
        if [ -f ".claude/settings.json" ] && ! $force; then
            echo "  Skipped .claude/settings.json (already exists, use -f to overwrite)"
        else
            cp "$settings_src" ".claude/settings.json"
            echo "  Installed .claude/settings.json"
        fi
    else
        echo "  Warning: settings.json not found at $settings_src"
    fi

    # Install slash commands from the repo's commands/ into .claude/commands/
    local commands_src="$cache_dir/commands"
    if [ -d "$commands_src" ]; then
        mkdir -p ".claude/commands"
        for cmd_file in "$commands_src"/*.md; do
            [ -f "$cmd_file" ] || continue
            local cmd_name=$(basename "$cmd_file")
            local cmd_dst=".claude/commands/$cmd_name"
            if [ -f "$cmd_dst" ] && ! $force; then
                echo "  Skipped command /$( basename "$cmd_name" .md) (already exists, use -f to overwrite)"
            else
                cp "$cmd_file" "$cmd_dst"
                echo "  Installed command /$(basename "$cmd_name" .md)"
            fi
        done
    fi

    # Install skills
    mkdir -p "$target_dir"
    local installed=0
    for skill in "${to_install[@]}"; do
        local src="$cache_dir/skills/$skill"
        local dst="$target_dir/$skill"

        if [ -d "$dst" ] && ! $force; then
            echo "  Skipped $skill (already exists, use -f to overwrite)"
            continue
        fi

        [ -e "$dst" ] && rm -rf "$dst"
        cp -r "$src" "$dst"
        echo "  Installed $skill"
        ((installed++))
    done

    echo "Done. $installed skill(s) installed to $target_dir/"

    # --- CLAUDE.md selection ---
    if [ -d "$cache_dir/claudemd" ]; then
        # Collect available modes
        # claudemd/global holds rules shared by every mode. It is appended to
        # whichever mode is installed, never offered as a mode of its own.
        local modes=()
        for mode_dir in "$cache_dir"/claudemd/*/; do
            [ -d "$mode_dir" ] || continue
            local mode_name=$(basename "$mode_dir")
            [ "$mode_name" = "global" ] && continue
            modes+=("$mode_name")
        done

        if [ ${#modes[@]} -eq 0 ]; then
            return 0
        fi

        local selected="$mode"
        local explicit_pick=false

        if [ -n "$selected" ]; then
            explicit_pick=true
        else
            # -f without -m: auto-detect the existing mode from the heading so the
            # user can re-sync CLAUDE.md silently without picking again.
            if [ -f "CLAUDE.md" ] && $force; then
                local current_head
                current_head=$(head -1 "CLAUDE.md")
                for m in "${modes[@]}"; do
                    if [ "$current_head" = "$(head -1 "$cache_dir/claudemd/$m/CLAUDE.md")" ]; then
                        selected="$m"
                        echo "  Detected existing CLAUDE.md mode: $selected"
                        break
                    fi
                done
            fi

            # No mode yet: prompt with fzf. This runs even when CLAUDE.md already
            # exists so the user can switch modes without first running with -f.
            if [ -z "$selected" ]; then
                if command -v fzf >/dev/null 2>&1; then
                    echo ""
                    selected=$(printf '%s\n' "${modes[@]}" | fzf --prompt="Select CLAUDE.md mode: " --height=10 --reverse)
                    if [ -n "$selected" ]; then
                        explicit_pick=true
                    elif [ -f "CLAUDE.md" ] && ! $force; then
                        echo "No mode selected; existing CLAUDE.md left untouched."
                        return 0
                    else
                        echo "No mode selected, defaulting to 'coding'."
                        selected="coding"
                    fi
                else
                    selected="coding"
                fi
            fi
        fi

        # Validate and install. An explicit pick (via -m or fzf) is treated as
        # consent to overwrite, so the user does not need -f in addition.
        local mode_src="$cache_dir/claudemd/$selected/CLAUDE.md"
        local global_src="$cache_dir/claudemd/global/CLAUDE.md"
        if [ -f "$mode_src" ]; then
            if [ -f "CLAUDE.md" ] && ! $force && ! $explicit_pick; then
                echo "CLAUDE.md already exists (use -f to overwrite, -m to switch mode)."
            else
                # Mode file first, so the mode auto-detection above keeps
                # matching on the first line when re-syncing with -f.
                cp "$mode_src" "CLAUDE.md"
                if [ -f "$global_src" ]; then
                    printf '\n' >> "CLAUDE.md"
                    cat "$global_src" >> "CLAUDE.md"
                    echo "  Installed CLAUDE.md (mode: $selected + global)"
                else
                    echo "  Installed CLAUDE.md (mode: $selected)"
                fi
            fi
        else
            echo "Warning: mode '$selected' not found. Available: ${modes[*]}"
        fi
    fi
}
