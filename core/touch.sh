# Set file last-modified time (now, absolute, or relative offset)
# Usage: mtime <file> [now | 2024-01-15 | 2024-01-15T14:30:00 | -2d3h30m15s]
mtime() {
    if [ $# -eq 0 ]; then
        echo "Usage: mtime <file> [time]"
        echo ""
        echo "  mtime file.txt                  # set to now"
        echo "  mtime file.txt now              # set to now"
        echo "  mtime file.txt 2024-01-15       # set to date (midnight)"
        echo "  mtime file.txt 2024-01-15T14:30:00  # set to datetime"
        echo "  mtime file.txt -2d3h30m15s      # 2 days, 3h, 30m, 15s ago"
        return 1
    fi

    local file="$1"
    local spec="${2:-now}"

    if [ ! -e "$file" ]; then
        echo "Error: '$file' not found" >&2
        return 1
    fi

    local ts

    case "$spec" in
        now)
            touch "$file"
            ;;

        # Relative offset: -2d3h30m15s
        -[0-9]*)
            ts=$(_mtime_relative "$spec") || return 1
            touch -t "$ts" "$file"
            ;;

        # Absolute: 2024-01-15 or 2024-01-15T14:30:00
        [0-9][0-9][0-9][0-9]-*)
            ts=$(_mtime_absolute "$spec") || return 1
            touch -t "$ts" "$file"
            ;;

        *)
            echo "Error: unrecognized format '$spec'" >&2
            echo "  Expected: now, YYYY-MM-DD, YYYY-MM-DDTHH:MM:SS, or -NdNhNmNs" >&2
            return 1
            ;;
    esac

    # Show result
    if [ $? -eq 0 ]; then
        local new_mtime
        if [[ "$OSTYPE" == "darwin"* ]]; then
            new_mtime=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$file")
        else
            new_mtime=$(stat -c "%y" "$file" | cut -d. -f1)
        fi
        echo "$file -> $new_mtime"
    fi
}

_mtime_absolute() {
    local spec="$1"
    local year month day hour min sec

    # Replace T with - for uniform parsing
    spec="${spec//T/-}"
    # Replace : with - too
    spec="${spec//:/-}"

    IFS='-' read -r year month day hour min sec <<< "$spec"
    hour="${hour:-00}"
    min="${min:-00}"
    sec="${sec:-00}"

    # Validate
    if [ -z "$year" ] || [ -z "$month" ] || [ -z "$day" ]; then
        echo "Error: invalid date format. Use YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS" >&2
        return 1
    fi

    # touch -t format: YYYYMMDDhhmm.ss
    printf "%s%s%s%s%s.%s" "$year" "$month" "$day" "$hour" "$min" "$sec"
}

_mtime_relative() {
    local spec="$1"
    local days=0 hours=0 mins=0 secs=0
    local num unit remaining

    # Strip leading -
    spec="${spec#-}"

    # Parse each component
    remaining="$spec"
    while [ -n "$remaining" ]; do
        # Extract leading number
        num="${remaining%%[a-z]*}"
        if [ -z "$num" ] || [ "$num" = "$remaining" ]; then
            echo "Error: invalid relative format. Use -NdNhNmNs (e.g. -2d3h30m)" >&2
            return 1
        fi
        remaining="${remaining#$num}"
        unit="${remaining:0:1}"
        remaining="${remaining:1}"

        case "$unit" in
            d) days=$num ;;
            h) hours=$num ;;
            m) mins=$num ;;
            s) secs=$num ;;
            *)
                echo "Error: unknown unit '$unit'. Use d/h/m/s" >&2
                return 1
                ;;
        esac
    done

    # Compute target timestamp
    local target
    if [[ "$OSTYPE" == "darwin"* ]]; then
        target=$(date -v-${days}d -v-${hours}H -v-${mins}M -v-${secs}S +"%Y%m%d%H%M.%S")
    else
        local total_secs=$(( days*86400 + hours*3600 + mins*60 + secs ))
        target=$(date -d "-${total_secs} seconds" +"%Y%m%d%H%M.%S")
    fi

    echo "$target"
}
