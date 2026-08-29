#!/usr/bin/env python3
"""Measure LexiFR lookup latency without loading the dictionary into memory."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sqlite3
import statistics
import time

from build_dictionary import normalize_search


SEARCH_SQL = """
WITH exact_matches AS (
    SELECT id, word, pos_title, normalized_word, 0 AS rank
      FROM entries
     WHERE normalized_word = :query
), word_matches AS (
    SELECT id, word, pos_title, normalized_word, 1 AS rank
      FROM entries INDEXED BY entries_normalized_word_idx
     WHERE normalized_word >= :query AND normalized_word < :upper
       AND normalized_word <> :query
     ORDER BY normalized_word, word
     LIMIT (:limit * 4)
), form_matches AS (
    SELECT e.id, e.word, e.pos_title, e.normalized_word, 2 AS rank
      FROM forms f INDEXED BY forms_normalized_idx
      JOIN entries e ON e.rowid = f.entry_rowid
     WHERE f.normalized_form >= :query AND f.normalized_form < :upper
     ORDER BY f.normalized_form, e.normalized_word, e.word
     LIMIT (:limit * 8)
), matches AS (
    SELECT * FROM exact_matches
    UNION ALL SELECT * FROM word_matches
    UNION ALL SELECT * FROM form_matches
)
SELECT id, word, pos_title
  FROM matches
 GROUP BY id
 ORDER BY MIN(rank), normalized_word, word
 LIMIT :limit
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", required=True, type=Path)
    parser.add_argument("--iterations", type=int, default=100)
    parser.add_argument("words", nargs="*", default=["école", "ecole", "épan", "coeur", "être"])
    args = parser.parse_args()

    connection = sqlite3.connect(f"file:{args.database.resolve()}?mode=ro", uri=True)
    report: dict[str, object] = {"database": str(args.database.resolve()), "iterations": args.iterations, "queries": {}}
    try:
        has_fts = connection.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='entry_fts'"
        ).fetchone() is not None
        report["fts5_available"] = has_fts
        for word in args.words:
            query = normalize_search(word)
            parameters = {"query": query, "upper": query + "\U0010ffff", "limit": 30}
            connection.execute(SEARCH_SQL, parameters).fetchall()  # warm cache
            timings = []
            result_count = 0
            for _ in range(args.iterations):
                start = time.perf_counter_ns()
                rows = connection.execute(SEARCH_SQL, parameters).fetchall()
                timings.append((time.perf_counter_ns() - start) / 1_000_000)
                result_count = len(rows)
            ordered = sorted(timings)
            query_report = {
                "normalized": query,
                "results": result_count,
                "median_ms": round(statistics.median(timings), 4),
                "p95_ms": round(ordered[max(0, int(len(ordered) * 0.95) - 1)], 4),
                "max_ms": round(max(timings), 4),
            }
            if has_fts:
                # Compare word-prefix lookup only. The production query also
                # searches forms, so FTS does not replace its semantics.
                fts_timings = []
                fts_term = '"' + query.replace('"', '""') + '"*'
                fts_sql = "SELECT rowid FROM entry_fts WHERE entry_fts MATCH ? LIMIT 30"
                connection.execute(fts_sql, (fts_term,)).fetchall()
                for _ in range(args.iterations):
                    start = time.perf_counter_ns()
                    connection.execute(fts_sql, (fts_term,)).fetchall()
                    fts_timings.append((time.perf_counter_ns() - start) / 1_000_000)
                fts_ordered = sorted(fts_timings)
                query_report["fts_prefix_median_ms"] = round(statistics.median(fts_timings), 4)
                query_report["fts_prefix_p95_ms"] = round(
                    fts_ordered[max(0, int(len(fts_ordered) * 0.95) - 1)], 4
                )
            report["queries"][word] = query_report
    finally:
        connection.close()
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
