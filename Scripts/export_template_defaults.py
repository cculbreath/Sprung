#!/usr/bin/env python3
"""
Export the active templates from the Sprung SwiftData store into bundle resources.

Usage:
    python Scripts/export_template_defaults.py \
        --store ~/Library/Containers/physicscloud.Sprung/Data/Library/Application\\ Support/default.store

The exporter writes the template catalog to Sprung/Resources/TemplateDefaults.
It overwrites existing files in that directory.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sqlite3
from datetime import datetime, timezone


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export Sprung template defaults")
    parser.add_argument(
        "--store",
        required=True,
        help="Path to the SwiftData SQLite store (e.g. default.store)",
    )
    parser.add_argument(
        "--output",
        default="Sprung/Resources/TemplateDefaults",
        help="Directory to write template resources (default: Sprung/Resources/TemplateDefaults)",
    )
    parser.add_argument(
        "--catalog-version",
        type=int,
        default=1,
        help="Version number written to catalog.json for tracking updates",
    )
    return parser.parse_args()


def ensure_clean_directory(path: pathlib.Path) -> None:
    if path.exists():
        for child in path.iterdir():
            if child.is_file():
                child.unlink()
            elif child.is_dir():
                ensure_clean_directory(child)
                child.rmdir()
    path.mkdir(parents=True, exist_ok=True)


def export_templates(store_path: pathlib.Path, output_dir: pathlib.Path, catalog_version: int) -> None:
    conn = sqlite3.connect(store_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    rows = cursor.execute(
        """
        SELECT
            ZNAME as name,
            ZSLUG as slug,
            ZISDEFAULT as is_default,
            ZHTMLCONTENT as html,
            ZTEXTCONTENT as text,
            ZMANIFESTDATA as manifest
        FROM ZTEMPLATE
        ORDER BY ZSLUG ASC
        """
    ).fetchall()

    templates = []
    for row in rows:
        slug = row["slug"]
        template_dir = output_dir / slug
        template_dir.mkdir(parents=True, exist_ok=True)

        html_path = template_dir / f"{slug}.html"
        text_path = template_dir / f"{slug}.txt"
        manifest_path = template_dir / f"{slug}.manifest.json"
        seed_path = template_dir / f"{slug}.seed.json"

        html_content = row["html"] or ""
        text_content = row["text"] or ""
        manifest_blob = row["manifest"] or b"{}"

        html_path.write_text(html_content, encoding="utf-8")
        text_path.write_text(text_content, encoding="utf-8")

        try:
            manifest_json = json.loads(manifest_blob.decode("utf-8"))
        except json.JSONDecodeError:
            manifest_json = manifest_blob.decode("utf-8")
        manifest_path.write_text(
            json.dumps(manifest_json, indent=2, sort_keys=True),
            encoding="utf-8",
        )

        seed_row = cursor.execute(
            """
            SELECT ZSEEDDATA as seed
            FROM ZTEMPLATESEED
            WHERE ZSLUG = ?
            ORDER BY ZUPDATEDAT DESC
            LIMIT 1
            """,
            (slug,),
        ).fetchone()

        if seed_row and seed_row["seed"]:
            try:
                seed_json = json.loads(seed_row["seed"].decode("utf-8"))
            except json.JSONDecodeError:
                seed_json = seed_row["seed"].decode("utf-8")
        else:
            seed_json = {}

        seed_path.write_text(
            json.dumps(seed_json, indent=2, sort_keys=True),
            encoding="utf-8",
        )

        templates.append(
            {
                "slug": slug,
                "name": row["name"],
                "isDefault": bool(row["is_default"]),
                "paths": {
                    "html": f"{slug}/{slug}.html",
                    "text": f"{slug}/{slug}.txt",
                    "manifest": f"{slug}/{slug}.manifest.json",
                    "seed": f"{slug}/{slug}.seed.json",
                },
            }
        )

    catalog = {
        "version": catalog_version,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "templates": templates,
    }

    catalog_path = output_dir / "catalog.json"
    catalog_path.write_text(
        json.dumps(catalog, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    conn.close()
    print(f"Wrote {len(templates)} templates to {output_dir}")


def main() -> None:
    args = parse_args()
    store_path = pathlib.Path(args.store).expanduser().resolve()
    output_dir = pathlib.Path(args.output)

    if not store_path.exists():
        raise SystemExit(f"Store not found: {store_path}")

    ensure_clean_directory(output_dir)
    export_templates(store_path, output_dir, args.catalog_version)


if __name__ == "__main__":
    main()
