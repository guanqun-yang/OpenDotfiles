# Install the user-level CLAUDE.md, and remove the stray $HOME one that would
# otherwise load into every project underneath it. Called once per invocation.
_claude_skills_user_md() {
    local cache_dir="$1" force="$2"
    if [ -f "$HOME/CLAUDE.md" ]; then
        rm -f "$HOME/CLAUDE.md"
        echo "Removed ~/CLAUDE.md (it loaded into every project under \$HOME)."
    fi

    local global_src="$cache_dir/claudemd/global/CLAUDE.md"
    local user_md="$HOME/.claude/CLAUDE.md"
    [ -f "$global_src" ] || return 0
    if [ ! -f "$user_md" ] || [ "$force" = true ] || [ "$(head -1 "$user_md")" = "$(head -1 "$global_src")" ]; then
        mkdir -p "$HOME/.claude"
        cp "$global_src" "$user_md"
        echo "Installed ~/.claude/CLAUDE.md (user layer)"
    else
        echo "~/.claude/CLAUDE.md exists and was not installed by claude-skills (use -f to overwrite)."
    fi
}

# Fetch Claude Skills from GitHub and install into current project's .claude/skills/
claude-skills() {
    local repo="https://github.com/guanqun-yang/OpenClaudeSkills.git"
    local cache_dir="$HOME/.cache/OpenClaudeSkills"
    local target_dir=".claude/skills"

    # Parse flags
    local force=false
    local list_only=false
    local all=false
    local dry_run=false
    local mode=""
    local skills=()
    # zsh aborts the function when a glob matches nothing; let empty dirs fall through.
    [ -n "$ZSH_VERSION" ] && setopt local_options null_glob
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force) force=true; shift ;;
            -l|--list)  list_only=true; shift ;;
            -a|--all)   all=true; force=true; shift ;;
            --dry-run)  dry_run=true; shift ;;
            -m|--mode)  mode="$2"; shift 2 ;;
            -h|--help)
                echo "Usage: claude-skills [options] [skill1 skill2 ...]"
                echo ""
                echo "Fetch Claude Skills from GitHub into .claude/skills/ of the current project,"
                echo "plus slash commands into .claude/commands/ and a CLAUDE.md based on use case (default: coding)."
                echo "Also installs the user-level ~/.claude/CLAUDE.md and removes any stray ~/CLAUDE.md."
                echo ""
                echo "Options:"
                echo "  -l, --list        List available skills, commands, and CLAUDE.md modes"
                echo "  -f, --force       Overwrite existing skills and both CLAUDE.md files"
                echo "  -a, --all         Re-install into every project under \$HOME that has"
                echo "                    .claude/skills already. Implies -f. Re-syncs a project's"
                echo "                    CLAUDE.md only when its first line matches a preset, so a"
                echo "                    hand-written one is left alone and no mode picker opens."
                echo "      --dry-run     With --all, list what would change and write nothing"
                echo "  -m, --mode MODE   Set CLAUDE.md mode (skip fzf selector)"
                echo "  -h, --help        Show this help"
                echo ""
                echo "Examples:"
                echo "  claude-skills                # install all skills, pick CLAUDE.md via fzf"
                echo "  claude-skills -m coding      # install all skills, use coding CLAUDE.md"
                echo "  claude-skills -m blog system-branding  # specific mode + skill"
                echo "  claude-skills -l             # list available skills and modes"
                echo "  claude-skills -f             # force update everything"
                echo "  claude-skills --all --dry-run  # show which projects would be updated"
                echo "  claude-skills --all          # update every installed project"
                return 0
                ;;
            *) skills+=("$1"); shift ;;
        esac
    done

    # Always sync with the GitHub remote. Clone if missing, fast-forward pull if present.
    # CS_CHILD is set by --all on each per-project run: the parent already synced,
    # and 40 fetches of the same repository is 40 chances to fail half way through.
    if [ -n "$CS_CHILD" ]; then
        :
    elif [ ! -d "$cache_dir/.git" ]; then
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

    # --- Update every installed project ---
    if $all; then
        # Declared once: in zsh, `local x` for a name that already exists prints it.
        local modes=() projects=() p p_mode head1 m updated=0 kept=0
        for mode_dir in "$cache_dir"/claudemd/*/; do
            [ -d "$mode_dir" ] || continue
            m=$(basename "$mode_dir")
            [ "$m" = "global" ] || modes+=("$m")
        done

        # A project is a directory with .claude/skills already in it. $HOME itself
        # is excluded: ~/.claude/skills is the user-level store, not an install.
        for p in $(find "$HOME" -maxdepth 3 -type d -path '*/.claude/skills' 2>/dev/null | sed 's|/.claude/skills$||' | sort); do
            [ "$p" = "$HOME" ] || projects+=("$p")
        done

        if [ ${#projects[@]} -eq 0 ]; then
            echo "No projects with .claude/skills found under $HOME."
            return 0
        fi

        $dry_run || _claude_skills_user_md "$cache_dir" true

        for p in "${projects[@]}"; do
            # Match the project's CLAUDE.md to a preset by its first line. No match
            # means it was hand-written, and overwriting it is the one thing this
            # loop must never do, so its CLAUDE.md is left exactly as it is.
            p_mode=""
            if [ -f "$p/CLAUDE.md" ]; then
                head1=$(head -1 "$p/CLAUDE.md")
                for m in "${modes[@]}"; do
                    if [ "$head1" = "$(head -1 "$cache_dir/claudemd/$m/CLAUDE.md")" ]; then
                        p_mode="$m"
                        break
                    fi
                done
            fi

            if $dry_run; then
                if [ -n "$p_mode" ]; then
                    printf "  %-44s skills + CLAUDE.md (%s)\n" "${p/#$HOME\//~/}" "$p_mode"
                elif [ -f "$p/CLAUDE.md" ]; then
                    printf "  %-44s skills only (CLAUDE.md hand-written)\n" "${p/#$HOME\//~/}"
                else
                    printf "  %-44s skills only (no CLAUDE.md)\n" "${p/#$HOME\//~/}"
                fi
                continue
            fi

            echo ""
            echo "==> ${p/#$HOME\//~/}"
            if [ -n "$p_mode" ]; then
                ( cd "$p" && CS_CHILD=1 claude-skills -f -m "$p_mode" ) && updated=$((updated + 1))
            else
                ( cd "$p" && CS_CHILD=1 CS_KEEP_CLAUDEMD=1 claude-skills -f ) && kept=$((kept + 1))
            fi
        done

        if $dry_run; then
            echo ""
            echo "${#projects[@]} project(s) would be updated. Run without --dry-run to apply."
        else
            echo ""
            echo "Done. $updated project(s) updated with their CLAUDE.md, $kept with skills only."
        fi
        return 0
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

    # --- User-level CLAUDE.md ---
    # Claude Code reads every CLAUDE.md from the working directory up to /, so a
    # file in $HOME silently loads into every project. The user layer belongs in
    # ~/.claude/CLAUDE.md, which is loaded everywhere by design. Under --all the
    # parent has already done this once.
    [ -n "$CS_CHILD" ] || _claude_skills_user_md "$cache_dir" "$force"

    # --- Project CLAUDE.md selection ---
    # CS_KEEP_CLAUDEMD is set by --all for a project whose CLAUDE.md matches no
    # preset: it was written by hand, so the skills update but the file does not.
    if [ -n "$CS_KEEP_CLAUDEMD" ]; then
        if [ -f "CLAUDE.md" ]; then
            echo "  Kept CLAUDE.md (hand-written, matches no preset)"
        else
            echo "  No CLAUDE.md here, and --all does not create one"
        fi
    elif [ -d "$cache_dir/claudemd" ]; then
        # Collect available modes; global is the user layer, never a mode.
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
        if [ -f "$mode_src" ]; then
            if [ -f "CLAUDE.md" ] && ! $force && ! $explicit_pick; then
                echo "CLAUDE.md already exists (use -f to overwrite, -m to switch mode)."
            else
                cp "$mode_src" "CLAUDE.md"
                echo "  Installed CLAUDE.md (mode: $selected)"
            fi
        else
            echo "Warning: mode '$selected' not found. Available: ${modes[*]}"
        fi
    fi
}
