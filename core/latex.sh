# Helper to ensure LaTeX dependencies are installed
_latex_ensure_dependency() {
  local cmd="$1"
  local package="$2"

  if ! command -v "$cmd" &> /dev/null; then
    echo "Command '$cmd' is required but not found."

    local install_cmd=""
    if command -v brew &> /dev/null; then
      install_cmd="brew install --cask mactex-no-gui"
    elif command -v apt-get &> /dev/null; then
      install_cmd="sudo apt-get update && sudo apt-get install -y texlive-full"
    elif command -v pacman &> /dev/null; then
      install_cmd="sudo pacman -S texlive-most"
    else
      echo "Could not detect a supported package manager (brew/apt/pacman)."
      echo "Please install TeX Live manually."
      return 1
    fi

    echo "To install, run: $install_cmd"
    read -p "Do you want to install TeX Live now? (y/N) " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo "Running: $install_cmd"
      eval "$install_cmd"
    else
      echo "Dependency missing. Aborting."
      return 1
    fi
  fi
}

# Compile LaTeX file to PDF with timestamp prefix: latex [filename]
latex() {
  # Default to main.tex if no argument provided
  local input_file="${1:-main.tex}"
  local base_name="${input_file%.tex}"

  # Validate input file exists
  if [[ ! -f "$input_file" ]]; then
    echo "Error: File '$input_file' not found"
    return 1
  fi

  # Ensure pdflatex is available
  _latex_ensure_dependency "pdflatex" "texlive" || return 1

  local timestamp=$(date +"%Y%m%d_%H%M%S")

  echo "Starting LaTeX compilation of $input_file..."

  # First pass
  echo "[1/5] Running pdflatex (first pass)..."
  pdflatex -interaction=nonstopmode -file-line-error "$input_file" > /dev/null 2>&1
  if [[ ! -f "$base_name.pdf" ]]; then
    echo "First pdflatex pass failed - no PDF generated. Check $base_name.log for details."
    return 1
  fi

  # Bibliography pass - detect biber (biblatex) vs bibtex
  if [[ -f "$base_name.bcf" ]]; then
    echo "[2/5] Running biber (biblatex detected)..."
    if command -v biber &> /dev/null; then
      biber "$base_name" > /dev/null 2>&1 || echo "Note: biber had some issues (this may be normal if no citations)."
    else
      echo "Warning: biblatex requires biber but it's not installed."
      _latex_ensure_dependency "biber" "biber" || return 1
      biber "$base_name" > /dev/null 2>&1
    fi
  else
    echo "[2/5] Running bibtex..."
    bibtex "$base_name" > /dev/null 2>&1 || echo "Note: bibtex had some issues (this may be normal if no citations)."
  fi

  # Second pass
  echo "[3/5] Running pdflatex (second pass)..."
  pdflatex -interaction=nonstopmode -file-line-error "$input_file" > /dev/null 2>&1

  # Third pass
  echo "[4/5] Running pdflatex (third pass)..."
  pdflatex -interaction=nonstopmode -file-line-error "$input_file" > /dev/null 2>&1

  # Check final PDF exists
  if [[ ! -f "$base_name.pdf" ]]; then
    echo "Compilation failed - no PDF generated. Check $base_name.log for details."
    return 1
  fi

  # Copy to timestamped output
  local output_name="${timestamp}_${base_name}.pdf"
  cp "$base_name.pdf" "$output_name"

  # Strip metadata
  echo "[5/5] Stripping PDF metadata..."
  if command -v exiftool &> /dev/null; then
    exiftool -all= -overwrite_original "$output_name" > /dev/null 2>&1
  elif command -v qpdf &> /dev/null; then
    qpdf --linearize --replace-input "$output_name" > /dev/null 2>&1
  else
    echo "Neither exiftool nor qpdf found for metadata stripping."
    local install_cmd=""
    if command -v brew &> /dev/null; then
      install_cmd="brew install exiftool"
    elif command -v apt-get &> /dev/null; then
      install_cmd="sudo apt-get install -y libimage-exiftool-perl"
    elif command -v pacman &> /dev/null; then
      install_cmd="sudo pacman -S perl-image-exiftool"
    fi

    if [[ -n "$install_cmd" ]]; then
      echo "To install exiftool, run: $install_cmd"
      read -p "Do you want to install exiftool now? (y/N) " -n 1 -r
      echo ""
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Running: $install_cmd"
        eval "$install_cmd"
        if command -v exiftool &> /dev/null; then
          exiftool -all= -overwrite_original "$output_name" > /dev/null 2>&1
        fi
      else
        echo "Skipping metadata stripping."
      fi
    else
      echo "Could not detect a supported package manager. Skipping metadata stripping."
    fi
  fi

  echo "Compilation successful!"
  echo "Output: $output_name"

  # Show page count if pdfinfo is available
  if command -v pdfinfo &> /dev/null; then
    local pages=$(pdfinfo "$output_name" 2>/dev/null | grep "Pages:" | awk '{print $2}')
    [[ -n "$pages" ]] && echo "Pages: $pages"
  fi

  # Open PDF with system default viewer
  if [[ "$OSTYPE" == "darwin"* ]]; then
    open "$output_name"
  elif command -v xdg-open &> /dev/null; then
    xdg-open "$output_name" &> /dev/null &
  else
    echo "Note: Could not detect a PDF viewer to open the file automatically."
  fi
}

# Clean LaTeX auxiliary files for .tex files in directory: latexclean [directory]
latexclean() {
  local dir="${1:-.}"
  local extensions=(aux log bbl blg toc out lof lot fls fdb_latexmk synctex.gz bcf run.xml)
  local count=0

  echo "Cleaning LaTeX auxiliary files in $dir..."

  # Only clean auxiliary files that correspond to existing .tex files
  for texfile in "$dir"/*.tex; do
    [[ -f "$texfile" ]] || continue
    local base="${texfile%.tex}"

    for ext in "${extensions[@]}"; do
      if [[ -f "$base.$ext" ]]; then
        rm "$base.$ext"
        ((count++))
      fi
    done
  done

  echo "Removed $count auxiliary file(s)."
}

# Open file in Texifier: texifier [filename]
texifier() {
  open -a Texifier "$1"
}
