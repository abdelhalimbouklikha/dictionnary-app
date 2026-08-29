#!/usr/bin/env python3
"""Build LexiFR's immutable SQLite dictionary from a Kaikki JSONL dump.

The importer is deliberately streaming: at no point is the source file loaded
in memory.  It accepts plain JSONL as well as gzip, bzip2 and xz streams.
"""

from __future__ import annotations

import argparse
import bz2
from collections import Counter
from contextlib import closing
from datetime import datetime, timezone
import gzip
import hashlib
import json
import lzma
from pathlib import Path
import re
import sqlite3
import sys
import time
import unicodedata
from typing import Any, BinaryIO, Iterable, Iterator, TextIO


SCHEMA_VERSION = "1"
APOSTROPHES = str.maketrans({
    "’": "'", "‘": "'", "ʼ": "'", "＇": "'", "`": "'", "´": "'",
    "œ": "oe", "Œ": "oe", "æ": "ae", "Æ": "ae",
})
SPACES = re.compile(r"\s+")
RELATION_FIELDS = (
    "synonyms", "antonyms", "hypernyms", "hyponyms", "holonyms",
    "meronyms", "derived", "related", "coordinate_terms", "paronyms",
    "abbreviations", "proverbs",
)


def normalize_search(value: str) -> str:
    """Return the accent/case-insensitive lookup form while preserving display text."""
    value = unicodedata.normalize("NFKC", value or "").translate(APOSTROPHES)
    value = SPACES.sub(" ", value.strip()).casefold()
    value = unicodedata.normalize("NFKD", value)
    value = "".join(char for char in value if not unicodedata.combining(char))
    return unicodedata.normalize("NFC", value)


def _json_strings(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, str) and item]


def _compact_json(value: Any) -> str | None:
    if value in (None, [], {}):
        return None
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def stable_entry_id(entry: dict[str, Any]) -> str:
    """Prefer Kaikki's stable sense identifier, with a deterministic fallback.

    Kaikki exposes an id on each source sense (observed in the real dump as
    ``fr-accueil-fr-noun-G53QnBh1``).  The first such id anchors an entry even
    if SQLite rowids change.  Rare entries without source ids use a SHA-256
    fingerprint of stable lexical fields.
    """
    senses = entry.get("senses")
    if isinstance(senses, list):
        for sense in senses:
            if isinstance(sense, dict) and isinstance(sense.get("id"), str):
                # The real dump reuses a sense id for numbered homograph
                # headings (for example "Forme de nom commun 3/4/5").  A
                # small deterministic heading discriminator keeps each entry
                # distinct without ever depending on SQLite's rowid.
                discriminator = "\0".join((
                    normalize_search(str(entry.get("word") or "")),
                    str(entry.get("pos") or "unknown"),
                    str(entry.get("pos_title") or ""),
                    str(entry.get("etymology_number") or ""),
                    json.dumps(_json_strings(entry.get("tags")), ensure_ascii=False),
                ))
                suffix = hashlib.sha256(discriminator.encode("utf-8")).hexdigest()[:12]
                return f"kaikki:{sense['id']}:{suffix}"

    word = normalize_search(str(entry.get("word") or ""))
    lang = str(entry.get("lang_code") or entry.get("lang") or "fr")
    pos = str(entry.get("pos") or entry.get("pos_title") or "unknown")
    etymology_number = str(entry.get("etymology_number") or "")
    etymology = "\n".join(_json_strings(entry.get("etymology_texts")))
    first_gloss = ""
    if isinstance(senses, list):
        for sense in senses:
            if isinstance(sense, dict):
                glosses = _json_strings(sense.get("glosses"))
                if glosses:
                    first_gloss = glosses[0]
                    break
    fingerprint = "\0".join((lang, word, pos, etymology_number, etymology, first_gloss))
    return "lexifr:" + hashlib.sha256(fingerprint.encode("utf-8")).hexdigest()[:32]


def _open_binary(path: Path) -> BinaryIO:
    return path.open("rb")


def open_jsonl(path: Path) -> TextIO:
    """Open a source based on magic bytes, not its possibly temporary suffix."""
    with _open_binary(path) as probe:
        magic = probe.read(6)
    if magic.startswith(b"\x1f\x8b"):
        stream: BinaryIO = gzip.open(path, "rb")
    elif magic.startswith(b"BZh"):
        stream = bz2.open(path, "rb")
    elif magic.startswith(b"\xfd7zXZ\x00"):
        stream = lzma.open(path, "rb")
    elif magic.startswith(b"(\xb5/\xfd"):
        raise RuntimeError(
            "Flux Zstandard détecté. Décompressez-le en JSONL, ou installez "
            "python-zstandard et adaptez open_jsonl()."
        )
    else:
        stream = _open_binary(path)
    import io
    # Replacement keeps the stream resumable after a malformed UTF-8 line; the
    # importer detects U+FFFD below and counts/skips that line explicitly.
    return io.TextIOWrapper(stream, encoding="utf-8", errors="replace", newline="")


def create_schema(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        CREATE TABLE metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        ) WITHOUT ROWID;

        CREATE TABLE entries (
            id TEXT PRIMARY KEY,
            word TEXT NOT NULL,
            normalized_word TEXT NOT NULL,
            pos_code TEXT NOT NULL,
            pos_title TEXT NOT NULL,
            gender TEXT,
            etymology TEXT,
            tags_json TEXT
        );

        CREATE TABLE senses (
            id INTEGER PRIMARY KEY,
            entry_rowid INTEGER NOT NULL,
            ordinal INTEGER NOT NULL,
            definition TEXT NOT NULL,
            tags_json TEXT
        );

        CREATE TABLE examples (
            id INTEGER PRIMARY KEY,
            sense_id INTEGER NOT NULL,
            ordinal INTEGER NOT NULL,
            text TEXT NOT NULL,
            source TEXT
        );

        CREATE TABLE pronunciations (
            id INTEGER PRIMARY KEY,
            entry_rowid INTEGER NOT NULL,
            ordinal INTEGER NOT NULL,
            ipa TEXT NOT NULL,
            region TEXT
        );

        CREATE TABLE forms (
            id INTEGER PRIMARY KEY,
            entry_rowid INTEGER NOT NULL,
            ordinal INTEGER NOT NULL,
            form TEXT NOT NULL,
            normalized_form TEXT NOT NULL,
            tags_json TEXT
        );

        CREATE TABLE relations (
            id INTEGER PRIMARY KEY,
            entry_rowid INTEGER NOT NULL,
            kind TEXT NOT NULL,
            word TEXT NOT NULL
        );
        """
    )


def _gender(entry: dict[str, Any]) -> str | None:
    tags = _json_strings(entry.get("tags"))
    labels = []
    for value in ("masculine", "feminine", "neuter", "common-gender"):
        if value in tags:
            labels.append(value)
    return ",".join(labels) or None


def _relation_word(item: Any) -> str | None:
    if isinstance(item, str):
        return item.strip() or None
    if isinstance(item, dict):
        for key in ("word", "form", "term"):
            value = item.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
    return None


class DictionaryWriter:
    def __init__(self, connection: sqlite3.Connection) -> None:
        self.connection = connection
        self.counts: Counter[str] = Counter()

    def add(self, entry: dict[str, Any]) -> bool:
        word = entry.get("word")
        if not isinstance(word, str) or not word.strip():
            return False
        if entry.get("lang_code") not in (None, "fr"):
            return False

        word = unicodedata.normalize("NFC", word.strip())
        normalized = normalize_search(word)
        if not normalized:
            return False
        entry_id = stable_entry_id(entry)
        pos_code = str(entry.get("pos") or "unknown")
        pos_title = str(entry.get("pos_title") or pos_code)
        etymology = "\n\n".join(_json_strings(entry.get("etymology_texts"))) or None
        tags = _json_strings(entry.get("tags"))
        cursor = self.connection.execute(
            """INSERT OR IGNORE INTO entries
               (id, word, normalized_word, pos_code, pos_title, gender, etymology, tags_json)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (entry_id, word, normalized, pos_code, pos_title,
             _gender(entry), etymology, _compact_json(tags)),
        )
        if cursor.rowcount == 0:
            self.counts["duplicate_entries"] += 1
            return False

        entry_rowid = int(cursor.lastrowid)

        self.counts["entries"] += 1

        seen_ipa: set[str] = set()
        sounds = entry.get("sounds")
        if isinstance(sounds, list):
            for sound in sounds:
                if not isinstance(sound, dict):
                    continue
                ipa = sound.get("ipa")
                if not isinstance(ipa, str) or not ipa.strip() or ipa in seen_ipa:
                    continue
                seen_ipa.add(ipa)
                raw_tags = _json_strings(sound.get("raw_tags"))
                self.connection.execute(
                    "INSERT INTO pronunciations(entry_rowid, ordinal, ipa, region) VALUES (?, ?, ?, ?)",
                    (entry_rowid, len(seen_ipa) - 1, ipa.strip(), ", ".join(raw_tags) or None),
                )
                self.counts["pronunciations"] += 1

        senses = entry.get("senses")
        if isinstance(senses, list):
            for sense_ordinal, sense in enumerate(senses):
                if not isinstance(sense, dict):
                    continue
                glosses = _json_strings(sense.get("glosses"))
                definition = " — ".join(glosses).strip()
                if not definition:
                    continue
                sense_cursor = self.connection.execute(
                    """INSERT INTO senses(entry_rowid, ordinal, definition, tags_json)
                       VALUES (?, ?, ?, ?)""",
                    (entry_rowid, sense_ordinal, definition,
                     _compact_json(_json_strings(sense.get("tags")))),
                )
                sense_id = int(sense_cursor.lastrowid)
                self.counts["senses"] += 1
                examples = sense.get("examples")
                if isinstance(examples, list):
                    for example_ordinal, example in enumerate(examples):
                        if not isinstance(example, dict):
                            continue
                        text = example.get("text")
                        if not isinstance(text, str) or not text.strip():
                            continue
                        self.connection.execute(
                            "INSERT INTO examples(sense_id, ordinal, text, source) VALUES (?, ?, ?, ?)",
                            (sense_id, example_ordinal, text.strip(), example.get("ref")),
                        )
                        self.counts["examples"] += 1

        forms = entry.get("forms")
        if isinstance(forms, list):
            seen_forms: set[tuple[str, str | None]] = set()
            for form_ordinal, form in enumerate(forms):
                if not isinstance(form, dict):
                    continue
                value = form.get("form")
                if not isinstance(value, str) or not value.strip():
                    continue
                value = unicodedata.normalize("NFC", value.strip())
                form_tags = _compact_json(_json_strings(form.get("tags")))
                key = (value, form_tags)
                if key in seen_forms:
                    continue
                seen_forms.add(key)
                self.connection.execute(
                    """INSERT INTO forms(entry_rowid, ordinal, form, normalized_form, tags_json)
                       VALUES (?, ?, ?, ?, ?)""",
                    (entry_rowid, form_ordinal, value, normalize_search(value), form_tags),
                )
                self.counts["forms"] += 1

        for relation_kind in RELATION_FIELDS:
            values = entry.get(relation_kind)
            if not isinstance(values, list):
                continue
            seen_relations: set[str] = set()
            for item in values:
                relation_word = _relation_word(item)
                if not relation_word or relation_word in seen_relations:
                    continue
                seen_relations.add(relation_word)
                self.connection.execute(
                    "INSERT INTO relations(entry_rowid, kind, word) VALUES (?, ?, ?)",
                    (entry_rowid, relation_kind, relation_word),
                )
                self.counts["relations"] += 1
        return True


def finalize_schema(connection: sqlite3.Connection, enable_fts: bool) -> None:
    connection.executescript(
        """
        CREATE INDEX entries_normalized_word_idx
            ON entries(normalized_word, word);
        CREATE INDEX senses_entry_idx ON senses(entry_rowid, ordinal);
        CREATE INDEX examples_sense_idx ON examples(sense_id, ordinal);
        CREATE INDEX pronunciations_entry_idx ON pronunciations(entry_rowid, ordinal);
        CREATE INDEX forms_normalized_idx ON forms(normalized_form, entry_rowid);
        CREATE INDEX forms_entry_idx ON forms(entry_rowid, ordinal);
        CREATE INDEX relations_entry_kind_idx ON relations(entry_rowid, kind);
        """
    )
    if enable_fts:
        connection.executescript(
            """
            CREATE VIRTUAL TABLE entry_fts USING fts5(
                word,
                normalized_word,
                pos_title,
                content='entries',
                content_rowid='rowid',
                tokenize='unicode61 remove_diacritics 2',
                prefix='2 3 4 5'
            );
            INSERT INTO entry_fts(rowid, word, normalized_word, pos_title)
                SELECT rowid, word, normalized_word, pos_title FROM entries;
            """
        )


def build_dictionary(
    input_path: Path,
    output_path: Path,
    *,
    limit: int | None,
    force: bool,
    batch_size: int,
    progress_every: int,
    enable_fts: bool,
) -> dict[str, Any]:
    if not input_path.is_file():
        raise FileNotFoundError(f"Source introuvable: {input_path}")
    stats_path = output_path.with_suffix(output_path.suffix + ".stats.json")
    if output_path.exists():
        if not force:
            raise FileExistsError(f"La sortie existe déjà: {output_path} (utilisez --force)")
        output_path.unlink()
    if force and stats_path.exists():
        stats_path.unlink()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    started = time.perf_counter()
    stats: dict[str, Any] = {
        "input": str(input_path.resolve()),
        "output": str(output_path.resolve()),
        "source_bytes": input_path.stat().st_size,
        "lines": 0,
        "valid_json": 0,
        "invalid_json": 0,
        "skipped": 0,
    }

    connection = sqlite3.connect(output_path)
    try:
        connection.executescript(
            """
            PRAGMA page_size=4096;
            PRAGMA journal_mode=OFF;
            PRAGMA synchronous=OFF;
            PRAGMA temp_store=MEMORY;
            PRAGMA cache_size=-262144;
            PRAGMA locking_mode=EXCLUSIVE;
            """
        )
        create_schema(connection)
        writer = DictionaryWriter(connection)
        connection.execute("BEGIN")

        with closing(open_jsonl(input_path)) as source:
            for line_number, line in enumerate(source, start=1):
                if limit is not None and stats["valid_json"] >= limit:
                    break
                stats["lines"] = line_number
                if "\ufffd" in line:
                    stats["invalid_json"] += 1
                    if stats["invalid_json"] <= 20:
                        print(f"[avertissement] ligne {line_number}: UTF-8 invalide", file=sys.stderr)
                    continue
                try:
                    entry = json.loads(line)
                    stats["valid_json"] += 1
                except (json.JSONDecodeError, UnicodeDecodeError) as error:
                    stats["invalid_json"] += 1
                    if stats["invalid_json"] <= 20:
                        print(f"[avertissement] ligne {line_number}: {error}", file=sys.stderr)
                    continue
                if not isinstance(entry, dict) or not writer.add(entry):
                    stats["skipped"] += 1

                if line_number % batch_size == 0:
                    connection.commit()
                    connection.execute("BEGIN")
                if line_number % progress_every == 0:
                    elapsed = max(time.perf_counter() - started, 0.001)
                    print(
                        f"{line_number:,} lignes | {writer.counts['entries']:,} entrées | "
                        f"{line_number / elapsed:,.0f} lignes/s",
                        flush=True,
                    )
        connection.commit()

        print("Création des index…", flush=True)
        finalize_schema(connection, enable_fts)
        stats.update(writer.counts)
        stats["distinct_words"] = int(
            connection.execute("SELECT count(DISTINCT normalized_word) FROM entries").fetchone()[0]
        )
        stats["fts5"] = enable_fts
        stats["schema_version"] = SCHEMA_VERSION
        stats["created_at"] = datetime.now(timezone.utc).isoformat()

        metadata = {
            "schema_version": SCHEMA_VERSION,
            "source_name": input_path.name,
            "source_bytes": str(stats["source_bytes"]),
            "created_at": stats["created_at"],
            "entry_count": str(stats.get("entries", 0)),
            "distinct_word_count": str(stats["distinct_words"]),
            "sense_count": str(stats.get("senses", 0)),
            "example_count": str(stats.get("examples", 0)),
            "pronunciation_count": str(stats.get("pronunciations", 0)),
            "form_count": str(stats.get("forms", 0)),
            "relation_count": str(stats.get("relations", 0)),
            "license": "CC BY-SA 4.0; GFDL (Wiktionnaire/Kaikki)",
        }
        connection.executemany("INSERT INTO metadata(key, value) VALUES (?, ?)", metadata.items())
        connection.commit()
        connection.execute("ANALYZE")
        connection.execute("PRAGMA optimize")
        connection.commit()
    except Exception:
        connection.close()
        if output_path.exists():
            output_path.unlink()
        raise
    else:
        connection.close()

    stats["database_bytes"] = output_path.stat().st_size
    stats["elapsed_seconds"] = round(time.perf_counter() - started, 3)
    stats_path.write_text(json.dumps(stats, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(stats, ensure_ascii=False, indent=2), flush=True)
    return stats


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="Dump Kaikki JSONL (brut/gz/bz2/xz)")
    parser.add_argument("--output", required=True, type=Path, help="Base SQLite à créer")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--limit", type=int, help="Nombre maximal de lignes JSON valides")
    group.add_argument("--sample", type=int, help="Alias explicite de --limit pour un prototype")
    parser.add_argument("--force", action="store_true", help="Remplacer la sortie existante")
    parser.add_argument("--batch-size", type=int, default=5_000)
    parser.add_argument("--progress-every", type=int, default=25_000)
    parser.add_argument("--fts", action="store_true", help="Créer l'index FTS5 optionnel (la recherche de l'app utilise le B-tree compact)")
    args = parser.parse_args(argv)
    if (args.limit or args.sample) is not None and (args.limit or args.sample) <= 0:
        parser.error("--limit/--sample doit être positif")
    if args.batch_size <= 0 or args.progress_every <= 0:
        parser.error("les tailles de batch/progression doivent être positives")
    return args


def main(argv: Iterable[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        build_dictionary(
            args.input,
            args.output,
            limit=args.limit if args.limit is not None else args.sample,
            force=args.force,
            batch_size=args.batch_size,
            progress_every=args.progress_every,
            enable_fts=args.fts,
        )
    except Exception as error:
        print(f"Erreur: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
