_arxiv_dl_help() {
    echo "Usage: arxiv-dl <id|file> [<id|file> ...]"
    echo ""
    echo "Download arXiv papers into the current directory as <id><version>.pdf."
    echo ""
    echo "Input:"
    echo "  IDs       2405.07314, 2405.07314v2, hep-th/9711200, arXiv:..., or arxiv.org URLs"
    echo "  Files     a file argument is read and every ID in it is downloaded"
    echo "  Any separator works (spaces, commas, semicolons, newlines...); duplicates are skipped."
    echo ""
    echo "Naming:"
    echo "  An ID without a version gets the latest version: 1706.03762 becomes 1706.03762v7.pdf"
    echo "  Old-style IDs replace '/' with '_': hep-th/9711200 becomes hep-th_9711200v3.pdf"
    echo ""
    echo "Examples:"
    echo "  arxiv-dl 1706.03762"
    echo "  arxiv-dl \"1706.03762v1, 1810.04805; hep-th/9711200\""
    echo "  arxiv-dl reading-list.txt"
    echo ""
    echo "Requires curl. Exits non-zero if any paper fails to download."
}

# Download arXiv papers into the current directory, named like 2405.07314v2.pdf: arxiv-dl ID-or-FILE ...
arxiv-dl() {
    case "$1" in
        -h|--help|help) _arxiv_dl_help; return 0 ;;
        "")             _arxiv_dl_help; return 1 ;;
    esac

    local text="" arg
    for arg in "$@"; do
        if [ -f "$arg" ]; then
            text="$text $(cat "$arg")"
        else
            text="$text $arg"
        fi
    done

    # Match IDs by pattern so any separator works: 2405.07314, 2405.07314v2, hep-th/9711200
    local ids
    ids=$(printf '%s\n' "$text" \
        | LC_ALL=C grep -oE '[a-z-]+(\.[A-Z]{2})?/[0-9]{7}(v[0-9]+)?|[0-9]{4}\.[0-9]{4,5}(v[0-9]+)?' \
        | awk '!seen[$0]++')
    if [ -z "$ids" ]; then
        echo "❌ No arXiv IDs found in input"
        return 1
    fi

    local id base ver name total=0 ok=0
    while IFS= read -r id; do
        total=$((total + 1))
        ver=$(printf '%s' "$id" | grep -oE 'v[0-9]+$')
        base="${id%"$ver"}"
        if [ -z "$ver" ]; then
            # arXiv names the latest version in the header, e.g. filename="1706.03762v7.pdf"
            ver=$(curl -fsSIL "https://arxiv.org/pdf/$base" \
                | grep -i '^content-disposition' | grep -oE 'v[0-9]+\.pdf' | tail -n 1)
            ver="${ver%.pdf}"
        fi
        if [ -z "$ver" ]; then
            echo "❌ $id  not found on arXiv"
            continue
        fi

        name="${base//\//_}$ver.pdf"
        if curl -fsSL -o "$name.part" "https://arxiv.org/pdf/$base$ver" && mv "$name.part" "$name"; then
            echo "✅ $name"
            ok=$((ok + 1))
        else
            rm -f "$name.part"
            echo "❌ $base$ver  download failed"
        fi
    done <<< "$ids"

    echo "$ok/$total downloaded to $PWD"
    [ "$ok" -eq "$total" ]
}
