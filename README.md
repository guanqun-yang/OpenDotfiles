# Dotfiles

Custom shell commands for macOS, organized as sourceable files instead of a sprawling `.zshrc`.

This repository is a curated public mirror — a private working repo holds the full set, and only the commands that are self-contained, macOS-native, and free of third-party services get published here. Nothing here needs an API key, an account, or a repository you cannot clone.

## The problem

Dumping custom scripts straight into `~/.zshrc` creates two headaches:

1. **Clutter** — the file becomes an unreadable pile of aliases, functions, and configuration.
2. **Version-control risk** — you cannot safely commit it without exposing whatever credentials ended up alongside your functions.

## The approach

Keep scripts in a dedicated folder, source them in a loop, and commit the folder.

```bash
git clone <this-repo> ~/dotfiles
```

Clone it to `~/dotfiles` specifically — several commands resolve their data files through `$HOME/dotfiles/data/`.

Then add to `~/.zshrc`:

```bash
# Source universal commands
if [ -d ~/dotfiles/core ]; then
    for file in ~/dotfiles/core/*.sh; do
        [ -r "$file" ] && source "$file"
    done
fi
# Source macOS-only commands
if [[ "$OSTYPE" == "darwin"* ]] && [ -d ~/dotfiles/macos ]; then
    for file in ~/dotfiles/macos/*.sh; do
        [ -r "$file" ] && source "$file"
    done
fi
```

Run `list_cmds` for a fuzzy-searchable index of everything that loaded.

## Structure

- **`core/`** — commands with no macOS-specific dependencies, sourced everywhere
- **`macos/`** — commands that call `osascript`, Finder, `pmset`, or other Apple-only interfaces
- **`data/`** — JSON files the commands read and write

The split is the loader's, not a portability promise: this mirror is curated for macOS, and a few `core/` commands lean on tools that happen to be installed there.

## Requirements

Most commands need [`fzf`](https://github.com/junegunn/fzf) and [`jq`](https://jqlang.github.io/jq/):

```bash
brew install fzf jq
```

Individual commands may want more — `pandoc` and a TeX distribution for `md2pdf`, `git` for `claude-skills` and `ref` — and each one says so when the tool is missing.

## Commands

<!-- COMMANDS:START -->

| Script | Commands | Description |
|---|---|---|
| `core/base.sh` | `list_cmds` | Fuzzy search custom commands with descriptions in preview |
| `core/cfg.sh` | `cfg` | Fuzzy search and copy frequently used configs stored in dotfiles/data/configs.json |
| `core/claude-skills.sh` | `claude-skills` | Fetch Claude Skills from GitHub and install into current project's .claude/skills/ |
| `core/cp.sh` | `cprecent` | Copy the k most recent files or folders from src to tgt: cprecent <src> <tgt> <k> |
| `core/git-anon.sh` | `git-anon`, `git-deanon` | Anonymize git user info and optionally rewrite history for anonymous repositories |
| `core/lookup.sh` | `lookup` | Open a search term in a URL template: lookup {add|delete|list|help|<term>} |
| `core/prompt.sh` | `prompt` | Manage prompt snippets: prompt {add|edit|delete|list|help} or fuzzy search |
| `core/pytab.sh` | `pytab` | Convert Python indentation between spaces and tabs |
| `core/ref.sh` | `ref` | Manage and sync reference material repos: ref [sync|add|edit|delete|list|help] |
| `core/touch.sh` | `mtime` | Set file last-modified time (now, absolute, or relative offset) Usage: mtime <file> [now | 2024-01-15 | 2024-01-15T14:30:00 | -2d3h30m15s] |
| `core/zip.sh` | `zipdate` | Zips the current folder with a timestamped filename |
| `macos/finder.sh` | `fav`, `unfav`, `lsfav` | `[macos]` Add a path to Finder sidebar Favorites |
| `macos/lidrun.sh` | `lidrun` | `[macos]` Run laptop with lid closed: lidrun {on|off|status|help} |
| `macos/md2pdf.sh` | `md2pdf` | `[macos]` Convert Markdown to PDF via Pandoc + XeLaTeX with minted code blocks Usage: md2pdf <input.md> [output.pdf] |

<!-- COMMANDS:END -->

## Data files

`data/` holds the state behind the fuzzy-search commands, as plain JSON you can edit by hand or through each command's `add` / `edit` / `delete` subcommands:

| File | Used by | Ships as |
|---|---|---|
| `configs.json` | `cfg` | A starting-point Claude Code permissions block |
| `lookups.json` | `lookup` | Google, Scholar, Wikipedia, GitHub, SEC EDGAR templates |
| `prompts.json` | `prompt` | Empty |
| `refs.json` | `ref` | Empty |

The empty ones are seeds — the private originals hold personal prompts and repositories. Run the matching command's `add` subcommand to fill them in.

## Claude Code skills

`claude-skills` installs the skills and `CLAUDE.md` templates from [OpenClaudeSkills](https://github.com/guanqun-yang/OpenClaudeSkills) into the current project's `.claude/` directory. It clones to `~/.cache/OpenClaudeSkills` and re-syncs on every run.

```bash
claude-skills -l              # list available skills and CLAUDE.md modes
claude-skills -m coding       # install everything with the coding CLAUDE.md
claude-skills -f              # re-sync, overwriting what is already there
```

## Notes

Implementation details worth writing down live in [`notes/`](notes/):

- [001-FINDER-SIDEBAR-FAVORITES](notes/001-FINDER-SIDEBAR-FAVORITES.md) — how Finder sidebar favorites are stored, and why `fav` / `unfav` work the way they do

## License

MIT
