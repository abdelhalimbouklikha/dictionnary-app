from __future__ import annotations

import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest


TOOLS = Path(__file__).resolve().parents[1]
ROOT = TOOLS.parent
sys.path.insert(0, str(TOOLS))

from build_dictionary import build_dictionary, normalize_search, stable_entry_id  # noqa: E402
from benchmark_dictionary import SEARCH_SQL  # noqa: E402


class NormalizationTests(unittest.TestCase):
    def test_french_diacritics_case_and_whitespace(self) -> None:
        self.assertEqual(normalize_search("  ÉCOLE  "), "ecole")
        self.assertEqual(normalize_search("é è ê ë à â ç ù û î ô"), "e e e e a a c u u i o")

    def test_ligatures_and_apostrophes(self) -> None:
        self.assertEqual(normalize_search("CŒUR"), "coeur")
        self.assertEqual(normalize_search("  L’ÉCOLE  "), "l'ecole")
        self.assertEqual(normalize_search("l`école"), "l'ecole")

    def test_stable_source_identifier(self) -> None:
        entry = {"word": "école", "lang_code": "fr", "pos": "noun", "senses": [{"id": "stable-42"}]}
        self.assertRegex(stable_entry_id(entry), r"^kaikki:stable-42:[0-9a-f]{12}$")
        self.assertEqual(stable_entry_id(entry), stable_entry_id(dict(entry)))


class DatabaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.database = Path(self.temp.name) / "fixture.sqlite"
        build_dictionary(
            ROOT / "Tests" / "Fixtures" / "test_dictionary.jsonl",
            self.database,
            limit=None,
            force=False,
            batch_size=2,
            progress_every=100,
            enable_fts=True,
        )
        self.connection = sqlite3.connect(self.database)

    def tearDown(self) -> None:
        self.connection.close()
        self.temp.cleanup()

    def search(self, value: str) -> list[str]:
        query = normalize_search(value)
        rows = self.connection.execute(
            SEARCH_SQL,
            {"query": query, "upper": query + "\U0010ffff", "limit": 30},
        ).fetchall()
        return [row[1] for row in rows]

    def test_counts_and_relations(self) -> None:
        self.assertEqual(self.connection.execute("SELECT count(*) FROM entries").fetchone()[0], 7)
        self.assertGreater(self.connection.execute("SELECT count(*) FROM senses").fetchone()[0], 0)
        self.assertGreater(self.connection.execute("SELECT count(*) FROM examples").fetchone()[0], 0)
        self.assertGreater(self.connection.execute("SELECT count(*) FROM relations").fetchone()[0], 0)

    def test_exact_accentless_and_prefix_search(self) -> None:
        self.assertEqual(self.search("ÉCOLE")[0], "école")
        self.assertIn("école", self.search("ecole"))
        self.assertEqual(self.search("épan")[:2], ["épanouir", "épanouissement"])

    def test_form_lookup(self) -> None:
        self.assertIn("être", self.search("suis"))
        self.assertIn("être", self.search("été"))

    def test_fts_is_available(self) -> None:
        count = self.connection.execute(
            "SELECT count(*) FROM entry_fts WHERE entry_fts MATCH ?", ("epan*",)
        ).fetchone()[0]
        self.assertEqual(count, 2)

    def test_metadata_and_stats(self) -> None:
        metadata = dict(self.connection.execute("SELECT key, value FROM metadata"))
        self.assertEqual(metadata["entry_count"], "7")
        stats = json.loads(self.database.with_suffix(".sqlite.stats.json").read_text(encoding="utf-8"))
        self.assertEqual(stats["invalid_json"], 0)

    def test_malformed_line_is_counted_and_skipped(self) -> None:
        source = Path(self.temp.name) / "malformed.jsonl"
        output = Path(self.temp.name) / "malformed.sqlite"
        valid_one = b'{"word":"un","lang_code":"fr","pos":"det","senses":[{"id":"one","glosses":["Un."]}]}\n'
        invalid = b'{"word":"broken-\xff"}\n'
        valid_two = b'{"word":"deux","lang_code":"fr","pos":"noun","senses":[{"id":"two","glosses":["Deux."]}]}'
        source.write_bytes(valid_one + invalid + valid_two)
        stats = build_dictionary(
            source,
            output,
            limit=None,
            force=False,
            batch_size=2,
            progress_every=100,
            enable_fts=False,
        )
        self.assertEqual(stats["invalid_json"], 1)
        self.assertEqual(stats["entries"], 2)


if __name__ == "__main__":
    unittest.main()
