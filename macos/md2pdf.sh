# Convert Markdown to PDF via Pandoc + XeLaTeX with minted code blocks
# Usage: md2pdf <input.md> [output.pdf]
md2pdf() {
    local input="$1"
    if [ -z "$input" ]; then
        echo "Usage: md2pdf <input.md> [output.pdf]"
        return 1
    fi
    if [ ! -f "$input" ]; then
        echo "Error: '$input' not found."
        return 1
    fi

    local output="${2:-${input%.*}.pdf}"

    local header filter
    header=$(mktemp -t md2pdf-XXXXXX).tex
    filter=$(mktemp -t md2pdf-XXXXXX).lua
    cat > "$header" << 'LATEX'
\usepackage{minted}
\definecolor{mintedbg}{rgb}{0.95,0.95,0.95}
\setminted{linenos=true,autogobble=true,breaklines=true,frame=lines,framesep=2mm,fontsize=\footnotesize,bgcolor=mintedbg}
\usepackage{xeCJK}
\setCJKmainfont{Songti SC}
LATEX

    cat > "$filter" << 'LUA'
 function CodeBlock(block)
  local lang = block.classes[1] or "text"
  return pandoc.RawBlock("latex",
    "\\begin{minted}{" .. lang .. "}\n" .. block.text .. "\n\\end{minted}")
end
LUA

    pandoc "$input" -o "$output" \
        -f markdown-raw_tex \
        --pdf-engine=xelatex \
        --pdf-engine-opt=-shell-escape \
        --toc \
        -V geometry:margin=1in \
        -V colorlinks=true \
        -V linkcolor=blue \
        -V fontsize=11pt \
        -V mainfont="Libertinus Serif" \
        -V mathfont="Libertinus Math" \
        -V monofont="Menlo" \
        -H "$header" \
        --lua-filter="$filter"
    local rc=$?

    rm -f "$header" "$filter"
    return $rc
}
