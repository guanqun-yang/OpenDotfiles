#!/usr/bin/env python3
"""Convert Python file indentation from spaces to tabs.

Usage:
    pytab.py <file>              # convert file in-place
    pytab.py <file> -o <output>  # convert to output file
    pytab.py -c                  # read from clipboard, write to clipboard
    pytab.py -                   # read from stdin, write to stdout
    pytab.py <file> -n <size>    # specify indent size (default: auto-detect)
"""

import argparse
import subprocess
import sys
from math import gcd
from functools import reduce


def detect_indent_size(text):
    """Detect the indentation unit size by finding the GCD of all leading-space counts."""
    indents = []
    for line in text.splitlines():
        stripped = line.lstrip(" ")
        if stripped and stripped != line:
            spaces = len(line) - len(stripped)
            if spaces > 0:
                indents.append(spaces)
    if not indents:
        return 4
    return reduce(gcd, indents)


def spaces_to_tabs(text, indent_size=None):
    """Convert leading spaces to tabs, preserving non-leading whitespace and blank lines."""
    if indent_size is None:
        indent_size = detect_indent_size(text)
        if indent_size < 2:
            indent_size = 4

    lines = text.splitlines(True)
    result = []
    for line in lines:
        stripped = line.lstrip(" ")
        num_spaces = len(line) - len(stripped)
        num_tabs = num_spaces // indent_size
        remainder = num_spaces % indent_size
        result.append("\t" * num_tabs + " " * remainder + stripped)
    return "".join(result)


def clipboard_read():
    return subprocess.check_output(["pbpaste"], text=True)


def clipboard_write(text):
    subprocess.run(["pbcopy"], input=text, text=True, check=True)


def main():
    parser = argparse.ArgumentParser(description="Convert Python indentation from spaces to tabs.")
    parser.add_argument("file", nargs="?", help="Input file (use - for stdin)")
    parser.add_argument("-o", "--output", help="Output file (default: in-place for files, stdout for stdin)")
    parser.add_argument("-c", "--clipboard", action="store_true", help="Read from and write to clipboard")
    parser.add_argument("-n", "--indent-size", type=int, default=None, help="Indent size in spaces (default: auto-detect)")
    args = parser.parse_args()

    if args.clipboard:
        text = clipboard_read()
        result = spaces_to_tabs(text, args.indent_size)
        clipboard_write(result)
        print(f"Converted clipboard (detected indent: {args.indent_size or detect_indent_size(text)} spaces -> tabs)")
        return

    if args.file == "-" or (args.file is None and not sys.stdin.isatty()):
        text = sys.stdin.read()
        result = spaces_to_tabs(text, args.indent_size)
        if args.output:
            with open(args.output, "w") as f:
                f.write(result)
        else:
            sys.stdout.write(result)
        return

    if args.file is None:
        parser.print_help()
        sys.exit(1)

    with open(args.file) as f:
        text = f.read()

    result = spaces_to_tabs(text, args.indent_size)
    out_path = args.output or args.file
    with open(out_path, "w") as f:
        f.write(result)

    detected = args.indent_size or detect_indent_size(text)
    print(f"Converted {args.file} ({detected} spaces -> tabs)" + (f" -> {out_path}" if args.output else ""))


if __name__ == "__main__":
    main()
