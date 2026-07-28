# Convert Python indentation between spaces and tabs
pytab() {
    case "$1" in
        clip) shift; python3 "$HOME/dotfiles/core/pytab.py" -c "$@" ;;
        help) echo "Usage: pytab [command] [args]"
              echo ""
              echo "Commands:"
              echo "  (none)    Convert file indentation from spaces to tabs"
              echo "  clip      Convert clipboard indentation from spaces to tabs"
              echo "  help      Show this help message" ;;
        *)    python3 "$HOME/dotfiles/core/pytab.py" "$@" ;;
    esac
}
