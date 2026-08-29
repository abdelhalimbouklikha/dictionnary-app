#!/usr/bin/env python3
"""Fail fast when a database is missing, corrupt or incompatible with LexiFR."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sqlite3


REQUIRED_TABLES = {"metadata", "entries", "senses", "examples", "pronunciations", "forms", "relations"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", required=True, type=Path)
    parser.add_argument("--minimum-entries", type=int, default=1)
    args = parser.parse_args()
    if not args.database.is_file():
        parser.error(f"base introuvable: {args.database}")
    connection = sqlite3.connect(f"file:{args.database.resolve()}?mode=ro", uri=True)
    try:
        integrity = connection.execute("PRAGMA quick_check").fetchone()[0]
        tables = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type IN ('table','view')")}
        missing = REQUIRED_TABLES - tables
        entries = connection.execute("SELECT count(*) FROM entries").fetchone()[0]
        metadata = dict(connection.execute("SELECT key, value FROM metadata"))
    finally:
        connection.close()
    report = {
        "database": str(args.database.resolve()),
        "bytes": args.database.stat().st_size,
        "integrity": integrity,
        "entries": entries,
        "schema_version": metadata.get("schema_version"),
        "missing_tables": sorted(missing),
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if integrity != "ok" or missing or entries < args.minimum_entries or metadata.get("schema_version") != "1":
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
