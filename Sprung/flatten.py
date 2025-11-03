#!/usr/bin/env python3
import os
import argparse
from pathlib import Path
from itertools import combinations

DIVIDER = "\n" + "=" * 80 + "\n"


def gather_swift_files(directory: Path):
    """Recursively find all .swift files under a directory."""
    return [
        p for p in directory.rglob("*")
        if p.suffix in [".swift", ".txt", ".md"]
        and not p.name.startswith("Merged_")
        and p.is_file()
    ]


def count_lines_in_dir(subdir: Path):
    """Count total lines across all Swift files in this directory."""
    total = 0
    for file in gather_swift_files(subdir):
        try:
            with file.open("r", encoding="utf-8", errors="ignore") as f:
                total += sum(1 for _ in f)
        except Exception:
            pass
    return total


def combine_swift_files(root: Path, subdirs: list[Path], output_dir: Path, merged_label=None):
    """
    Combine all Swift files from one or more subdirs into a single .txt file with headers.
    Returns index entries (start line, filename, LOC, rel path).
    """
    all_files = []
    for s in subdirs:
        all_files.extend(gather_swift_files(s))

    if not all_files:
        return None

    # Build output filename
    if len(subdirs) == 1:
        out_name = subdirs[0].name
    else:
        names = "+".join(s.name for s in subdirs)
        out_name = f"Merged_{names}"

    out_file = output_dir / f"{out_name}.txt"
    index_entries = []
    line_counter = 1

    with out_file.open("w", encoding="utf-8") as out:
        for file in sorted(all_files):
            rel_path = file.relative_to(root)
            header = f"{DIVIDER}// FILE: {rel_path}\n{DIVIDER}\n"
            out.write(header)
            start_line = line_counter
            header_lines = header.count("\n")
            line_counter += header_lines

            with file.open("r", encoding="utf-8", errors="ignore") as f:
                contents = f.read()
                out.write(contents)
                file_line_count = contents.count("\n") + 1
                index_entries.append((start_line, rel_path.name, file_line_count, rel_path))
                line_counter += file_line_count
                out.write("\n")

    merged_label = merged_label or (subdirs[0].name if len(subdirs) == 1 else f"Merged_{'+'.join(s.name for s in subdirs)}")
    return merged_label, index_entries


def merge_smallest_dirs(dir_locs: dict[str, int], max_files: int):
    """
    Merge smallest directories by LOC until only max_files remain.
    Returns a list of lists of dir names (groups).
    """
    groups = [[d] for d in dir_locs.keys()]
    locs = {d: dir_locs[d] for d in dir_locs}

    while len(groups) > max_files:
        # Find two groups with smallest combined LOC
        smallest = sorted(groups, key=lambda g: sum(locs[d] for d in g))
        g1, g2 = smallest[0], smallest[1]
        new_group = g1 + g2

        # Rebuild locs and groups
        groups.remove(g1)
        groups.remove(g2)
        groups.append(new_group)
        new_key = "+".join(new_group)
        locs[new_key] = sum(locs[d] for d in new_group if d in locs)

    return groups


def create_index_file(index_data, output_dir: Path, merge_info: dict[str, list[str]]):
    """Create a tree-like index file listing all subdirectories and their files."""
    index_file = output_dir / "SourceIndex.txt"
    with index_file.open("w", encoding="utf-8") as idx:
        idx.write(".\n")
        idx.write("│\n")
        idx.write("│  KEY:\n")
        idx.write("│    <number>  = line number where this file starts in the .txt file\n")
        idx.write("│    (<N> lines) = total number of lines of Swift code for that file\n")
        idx.write("│\n")
        idx.write("│  Example:  151  - InterviewOrchestrator.swift (22 lines)\n")
        idx.write("│           ↑start│          │ file length → 22 lines\n")
        idx.write("│\n")

        for out_name, entries in sorted(index_data.items()):
            if out_name in merge_info:
                merged_dirs = ", ".join(merge_info[out_name])
                idx.write(f"├── {out_name}.txt  (merged: {merged_dirs})\n")
            else:
                idx.write(f"├── {out_name}.txt\n")
            for i, (start_line, filename, loc, rel_path) in enumerate(entries):
                branch = "│   ├── " if i < len(entries) - 1 else "│   └── "
                idx.write(f"{branch}{start_line:<5} - {filename} ({loc} lines)\n")
            idx.write("│\n")

    print(f"Created index file: {index_file}")


def main():
    parser = argparse.ArgumentParser(
        description="Flatten Swift files from subdirectories into combined text files with an index, merging smallest ones if needed."
    )
    parser.add_argument("root_dir", type=str, help="Root directory to process")
    parser.add_argument(
        "-o", "--output", type=str, default="flattened_output",
        help="Directory to save combined text and index files (default: ./flattened_output)"
    )
    parser.add_argument(
        "-m", "--max-files", type=int, default=None,
        help="Maximum number of text files to produce (merging smallest dirs if exceeded)"
    )
    args = parser.parse_args()

    root = Path(args.root_dir).resolve()
    output_dir = Path(args.output).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    # --- Count LOC per directory ---
    dir_locs = {}
    subdirs = [d for d in sorted(root.iterdir()) if d.is_dir()]
    for d in subdirs:
        total = count_lines_in_dir(d)
        dir_locs[d.name] = total
        print(f"Directory {d.name}: {total} LOC")

    # --- Decide grouping ---
    groups = [[d.name] for d in subdirs]
    if args.max_files and len(subdirs) > args.max_files:
        target_files = max(args.max_files - 1, 1)  # reserve one slot for index.txt
        print(f"Merging {len(subdirs)} directories down to {target_files} flattened files (+ index = {args.max_files} total)...")
        groups = merge_smallest_dirs(dir_locs, target_files)

    # --- Flatten each group ---
    index_data = {}
    merge_info = {}
    for group in groups:
        dirs_to_merge = [root / g for g in group]
        merged_label, entries = combine_swift_files(root, dirs_to_merge, output_dir)
        if entries:
            index_data[merged_label] = entries
            if len(group) > 1:
                merge_info[merged_label] = group

    # --- Create index ---
    if index_data:
        create_index_file(index_data, output_dir, merge_info)
        print(f"All done. Output written to: {output_dir}")
    else:
        print("No Swift files found in any top-level subdirectory.")


if __name__ == "__main__":
    main()