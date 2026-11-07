#!/usr/bin/env python3
"""Remove whole-line comments from Python files in place.

Usage: strip_comments.py FILE [FILE ...]

Uses the tokenizer, so lines starting with '#' inside strings stay untouched.
Inline comments after code and shebang lines ('#!') are kept.
"""
import io
import sys
import tokenize


def strip_file(path: str) -> None:
    with open(path, encoding="utf-8") as source:
        text = source.read()

    lines = io.StringIO(text).readlines()
    drop_rows = set()
    for token in tokenize.generate_tokens(io.StringIO(text).readline):
        if token.type != tokenize.COMMENT:
            continue
        row, col = token.start
        line = lines[row - 1]
        if line[:col].strip() == "" and not line.startswith("#!"):
            drop_rows.add(row)

    kept = [line for row, line in enumerate(lines, start=1) if row not in drop_rows]
    with open(path, "w", encoding="utf-8") as target:
        target.writelines(kept)


def main() -> None:
    for path in sys.argv[1:]:
        strip_file(path)


if __name__ == "__main__":
    main()
