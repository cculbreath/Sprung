#!/usr/bin/env python3
"""
Utility to redact oversized lines in text logs.

Usage:
    python Scripts/redact_large_lines.py --input <input-path> --output <output-path> [--limit 4000]

Lines longer than the specified limit are replaced with a placeholder so the
resulting file remains readable and lightweight.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Iterable


PLACEHOLDER = "[redacted for brevity; original length: {length} chars]"


def redact_lines(lines: Iterable[str], limit: int) -> Iterable[str]:
    """
    Yield lines, replacing any whose length exceeds `limit`.
    """
    for line in lines:
        yield line if len(line) <= limit else PLACEHOLDER.format(length=len(line)) + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Redact oversized lines in a text file.")
    parser.add_argument(
        "--input",
        required=True,
        type=Path,
        help="Path to the source text file.",
    )
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="Path to write the redacted output.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=4000,
        help="Maximum allowed line length before redaction (default: 4000).",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    with args.input.open("r", encoding="utf-8") as src:
        redacted = list(redact_lines(src, args.limit))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as dst:
        dst.writelines(redacted)


if __name__ == "__main__":
    main()
