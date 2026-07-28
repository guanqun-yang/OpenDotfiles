# Copy the k most recent files or folders from src to tgt: cprecent <src> <tgt> <k>
cprecent() {
    if [ $# -ne 3 ]; then
        echo "Usage: cprecent <src> <tgt> <k>"
        return 1
    fi

    local src="$1"
    local tgt="$2"
    local k="$3"

    if [ ! -d "$src" ]; then
        echo "Error: Source directory '$src' does not exist"
        return 1
    fi

    if ! [[ "$k" =~ ^[0-9]+$ ]] || [ "$k" -eq 0 ]; then
        echo "Error: k must be a positive integer"
        return 1
    fi

    mkdir -p "$tgt"

    ls -t "$src" | head -n "$k" | while read -r item; do
        [ -e "$src/$item" ] && cp -r "$src/$item" "$tgt/"
    done
}