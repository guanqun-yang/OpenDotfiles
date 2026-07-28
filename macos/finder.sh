# Find a python3 that has PyObjC (CoreServices module)
_finder_python() {
    local p
    for p in /opt/anaconda3/bin/python3 /opt/homebrew/bin/python3 /usr/bin/python3 python3; do
        if command -v "$p" &>/dev/null && "$p" -c "from CoreServices import LSSharedFileListCreate" 2>/dev/null; then
            echo "$p"
            return
        fi
    done
    echo "Error: no python3 with PyObjC found" >&2
    return 1
}

# Add a path to Finder sidebar Favorites
fav() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        echo "Error: fav only works on macOS" >&2
        return 1
    fi

    local py
    py=$(_finder_python) || return 1

    local target

    if [ $# -eq 0 ]; then
        target="$(pwd)"
    else
        target="$1"
    fi

    # Resolve to absolute path
    target="$(cd "$target" 2>/dev/null && pwd)" || {
        echo "Error: '$1' is not a valid directory" >&2
        return 1
    }

    "$py" -c "
import sys
from Foundation import NSURL
from CoreServices import (
    kLSSharedFileListFavoriteItems,
    LSSharedFileListCreate,
    LSSharedFileListInsertItemURL,
    LSSharedFileListCopySnapshot,
    LSSharedFileListItemCopyResolvedURL,
    kLSSharedFileListItemLast,
)

path = sys.argv[1]
url = NSURL.fileURLWithPath_(path)

lst = LSSharedFileListCreate(None, kLSSharedFileListFavoriteItems, None)
if lst is None:
    print('Error: could not access Finder sidebar', file=sys.stderr)
    sys.exit(1)

# Check if already in favorites
items, _ = LSSharedFileListCopySnapshot(lst, None)
for item in items:
    item_url, _ = LSSharedFileListItemCopyResolvedURL(item, 0, None)
    if item_url and item_url.path() == path:
        print(f'Already in Favorites: {path}')
        sys.exit(0)

item = LSSharedFileListInsertItemURL(lst, kLSSharedFileListItemLast, None, None, url, None, None)
if item:
    print(f'Added to Favorites: {path}')
else:
    print('Error: failed to add item', file=sys.stderr)
    sys.exit(1)
" "$target"
}

# Remove a path from Finder sidebar Favorites
# With no args: interactive multi-select via fzf
# With args: remove the specified path directly
unfav() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        echo "Error: unfav only works on macOS" >&2
        return 1
    fi

    local py
    py=$(_finder_python) || return 1

    if [ $# -eq 0 ]; then
        if ! command -v fzf &>/dev/null; then
            echo "Error: fzf is required for interactive mode. Install with: brew install fzf" >&2
            return 1
        fi

        local selections
        selections=$("$py" -c "
from CoreServices import (
    kLSSharedFileListFavoriteItems,
    LSSharedFileListCreate,
    LSSharedFileListCopySnapshot,
    LSSharedFileListItemCopyResolvedURL,
    LSSharedFileListItemCopyDisplayName,
)

lst = LSSharedFileListCreate(None, kLSSharedFileListFavoriteItems, None)
items, _ = LSSharedFileListCopySnapshot(lst, None)
for item in items:
    name = LSSharedFileListItemCopyDisplayName(item)
    url, _ = LSSharedFileListItemCopyResolvedURL(item, 0, None)
    path = url.path() if url else ''
    if path:
        print(f'{name}\t{path}')
" | fzf --multi --with-nth=1 --delimiter='\t' \
        --header='Select favorites to remove (TAB to multi-select, ENTER to confirm)' \
        --preview='ls -la {2}' \
        --preview-window=down,3)

        [ -z "$selections" ] && return 0

        echo "$selections" | while IFS=$'\t' read -r name path; do
            unfav "$path"
        done
        return
    fi

    local target="$1"
    target="$(cd "$target" 2>/dev/null && pwd)" || {
        echo "Error: '$1' is not a valid directory" >&2
        return 1
    }

    "$py" -c "
import sys
from Foundation import NSURL
from CoreServices import (
    kLSSharedFileListFavoriteItems,
    LSSharedFileListCreate,
    LSSharedFileListCopySnapshot,
    LSSharedFileListItemCopyResolvedURL,
    LSSharedFileListItemRemove,
)

path = sys.argv[1]
lst = LSSharedFileListCreate(None, kLSSharedFileListFavoriteItems, None)
if lst is None:
    print('Error: could not access Finder sidebar', file=sys.stderr)
    sys.exit(1)

items, _ = LSSharedFileListCopySnapshot(lst, None)
for item in items:
    item_url, _ = LSSharedFileListItemCopyResolvedURL(item, 0, None)
    if item_url and item_url.path() == path:
        LSSharedFileListItemRemove(lst, item)
        print(f'Removed from Favorites: {path}')
        sys.exit(0)

print(f'Not in Favorites: {path}')
sys.exit(1)
" "$target"
}

# List all Finder sidebar Favorites
lsfav() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        echo "Error: lsfav only works on macOS" >&2
        return 1
    fi

    local py
    py=$(_finder_python) || return 1

    "$py" -c "
from CoreServices import (
    kLSSharedFileListFavoriteItems,
    LSSharedFileListCreate,
    LSSharedFileListCopySnapshot,
    LSSharedFileListItemCopyResolvedURL,
    LSSharedFileListItemCopyDisplayName,
)

lst = LSSharedFileListCreate(None, kLSSharedFileListFavoriteItems, None)
items, _ = LSSharedFileListCopySnapshot(lst, None)
for item in items:
    name = LSSharedFileListItemCopyDisplayName(item)
    url, _ = LSSharedFileListItemCopyResolvedURL(item, 0, None)
    path = url.path() if url else '(unresolvable)'
    print(f'  {name}: {path}')
"
}
