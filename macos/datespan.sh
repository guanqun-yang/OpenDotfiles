# Compute aggregate days between multiple date pairs
# Usage: datespan
datespan() {
    local CYAN='\033[36m' GREEN='\033[32m' YELLOW='\033[33m'
    local RED='\033[31m' BOLD='\033[1m' DIM='\033[2m' RESET='\033[0m'

    local -a starts=() ends=() days_list=()
    local inclusive=1

    _ds_to_epoch() {
        date -jf "%Y-%m-%d" "$1" "+%s" 2>/dev/null
    }

    _ds_parse_date() {
        local input="${1// /}"
        # YYYY-MM-DD
        if [[ "$input" =~ ^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}$ ]]; then
            _ds_to_epoch "$input" >/dev/null && _ds_result="$input" && return 0
        fi
        # MM/DD/YYYY
        if [[ "$input" =~ ^([0-9]{1,2})/([0-9]{1,2})/([0-9]{4})$ ]]; then
            local converted="${match[3]}-${match[1]}-${match[2]}"
            _ds_to_epoch "$converted" >/dev/null && _ds_result="$converted" && return 0
        fi
        # MM/DD/YY
        if [[ "$input" =~ ^([0-9]{1,2})/([0-9]{1,2})/([0-9]{2})$ ]]; then
            local converted="20${match[3]}-${match[1]}-${match[2]}"
            _ds_to_epoch "$converted" >/dev/null && _ds_result="$converted" && return 0
        fi
        return 1
    }

    _ds_days_between() {
        local e1 e2 diff
        e1=$(_ds_to_epoch "$1")
        e2=$(_ds_to_epoch "$2")
        diff=$(( (e2 - e1) / 86400 ))
        diff="${diff#-}"
        echo $((diff + inclusive))
    }

    _ds_print_summary() {
        local total=0 count=${#starts[@]}
        [[ $count -eq 0 ]] && return
        printf "\n${BOLD}%-4s│ %-12s│ %-12s│ %s${RESET}\n" "  #" " Start" " End" " Days"
        printf '%.0s─' {1..46}; echo
        local i
        for ((i = 1; i <= count; i++)); do
            total=$((total + days_list[i]))
            printf "  %d │ %s │ %s │ ${CYAN}%5d${RESET}\n" \
                "$i" "${starts[i]}" "${ends[i]}" "${days_list[i]}"
        done
        printf '%.0s─' {1..46}; echo
        local mode_label="exclusive"
        [[ $inclusive -eq 1 ]] && mode_label="inclusive"
        printf "${BOLD}${GREEN}  Aggregate total: %d days${RESET} ${DIM}(%s)${RESET}\n\n" "$total" "$mode_label"
    }

    _ds_recalc_all() {
        local i
        for ((i = 1; i <= ${#starts[@]}; i++)); do
            days_list[i]=$(_ds_days_between "${starts[i]}" "${ends[i]}")
        done
    }

    printf "${BOLD}Date Span Calculator${RESET}\n"
    printf "${DIM}Enter date pairs: start, end  (e.g. 2024-01-01, 2024-01-31)${RESET}\n"
    printf "${DIM}Commands: del N, mode, blank to finish.${RESET}\n"
    printf "${DIM}Mode: inclusive (both endpoints counted).${RESET}\n\n"

    trap 'echo; _ds_print_summary; return 0' INT

    local line _ds_result
    while true; do
        printf "${DIM}[%d] ${RESET}" "$((${#starts[@]} + 1))"
        read "line?"
        # Empty or quit
        [[ -z "$line" || "$line" == "q" ]] && { _ds_print_summary; break; }

        # Commands
        case "$line" in
            del\ [0-9]*)
                local idx="${line#del }"
                if [[ $idx -ge 1 && $idx -le ${#starts[@]} ]]; then
                    printf "  Deleted pair %d (%s → %s).\n" "$idx" "${starts[idx]}" "${ends[idx]}"
                    starts[$idx]=()
                    ends[$idx]=()
                    days_list[$idx]=()
                    _ds_print_summary
                else
                    printf "  ${RED}No pair #%s.${RESET}\n" "$idx"
                fi
                continue
                ;;
            mode)
                if [[ $inclusive -eq 1 ]]; then
                    inclusive=0
                    printf "  Switched to ${BOLD}exclusive${RESET} (end - start).\n"
                else
                    inclusive=1
                    printf "  Switched to ${BOLD}inclusive${RESET} (both endpoints counted).\n"
                fi
                _ds_recalc_all
                _ds_print_summary
                continue
                ;;
        esac

        # Parse "start, end" pair
        local left="${line%%,*}"
        local right="${line#*,}"

        if [[ "$left" == "$line" ]]; then
            printf "  ${RED}Enter two dates separated by a comma: start, end${RESET}\n"
            continue
        fi

        if ! _ds_parse_date "$left"; then
            printf "  ${RED}Invalid start date: %s${RESET}\n" "$left"
            continue
        fi
        local s="$_ds_result"

        if ! _ds_parse_date "$right"; then
            printf "  ${RED}Invalid end date: %s${RESET}\n" "$right"
            continue
        fi
        local e="$_ds_result"

        starts+=("$s")
        ends+=("$e")
        days_list+=($(_ds_days_between "$s" "$e"))
        _ds_print_summary
    done
}
