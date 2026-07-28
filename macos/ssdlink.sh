# Create /Volumes/SSD/<name> and symlink it into $HOME
ssdlink() {
    if [ $# -ne 1 ]; then
        echo "Usage: ssdlink <name>"
        return 1
    fi

    local name="$1"
    local src="/Volumes/SSD/${name}"
    local link="$HOME/${name}"

    if [ ! -d "/Volumes/SSD" ]; then
        echo "Error: /Volumes/SSD is not mounted" >&2
        return 1
    fi

    if [ -e "$link" ] || [ -L "$link" ]; then
        echo "Error: $link already exists" >&2
        return 1
    fi

    mkdir -p "$src"
    ln -s "$src" "$link"
    echo "Linked: $link -> $src"
}

# eza listing with SSD-backed symlinks highlighted in bold yellow
ssdls() {
    if ! command -v eza &>/dev/null; then
        echo "Error: eza is required. Install with: brew install eza" >&2
        return 1
    fi
    eza -la --color=always "$@" | perl -pe 's|(\x1b\[[0-9;]*m)?(/Volumes/SSD)|\e[1;33m$2|g'
}
