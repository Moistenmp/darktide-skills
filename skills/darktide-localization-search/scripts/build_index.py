"""Build an independent Darktide localization index from readable SJSON files."""

import argparse
import json
import os
import sqlite3
import sys
import tempfile
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

from common import (CODES, HEX_HASH, SCRIPTS, columns_sql, fingerprint, key_hash,
                    open_index, print_json, read_records, source_keys)


@contextmanager
def temporary_build(root):
    root.mkdir(exist_ok=True)
    try:
        with tempfile.TemporaryDirectory(prefix="localization-", dir=root) as temporary:
            yield Path(temporary)
    finally:
        if not any(root.iterdir()):
            root.rmdir()


def build(args):
    root = args.strings.resolve(strict=True)
    if not root.is_dir():
        raise ValueError("--strings must be a directory")
    paths = sorted(root.rglob("*.strings"))
    if not paths:
        raise ValueError("No .strings files found")
    database = args.db.resolve()
    if database.exists():
        if not args.replace:
            raise ValueError("Database exists; use --replace to rebuild this skill's index")
        open_index(database).close()
    keys = source_keys(args.source, args.keys_file)
    inputs = [fingerprint(path) for path in paths]
    count = 0
    with temporary_build(args.temp_root.resolve()) as temporary:
        staged = temporary / "index.sqlite"
        connection = sqlite3.connect(staged)
        try:
            schema = (SCRIPTS / "schema.sql").read_text(encoding="utf-8")
            connection.executescript(schema.replace("/*COLUMNS*/", columns_sql()))
            insert = "INSERT INTO localization VALUES (" + ",".join("?" for _ in range(len(CODES) + 2)) + ")"
            with connection:
                for path in paths:
                    resource = path.relative_to(root).as_posix()
                    for hashed, name, values in read_records(path):
                        connection.execute(insert, (resource, hashed, *(values.get(code) for code in CODES)))
                        if not HEX_HASH.fullmatch(name):
                            keys.add(name)
                        count += 1
                if not count:
                    raise ValueError("No localization records found")
                connection.executemany("INSERT INTO key_names VALUES (?, ?)",
                                       ((key_hash(key), key) for key in sorted(keys)))
                info = {
                    "created_utc": datetime.now(timezone.utc).isoformat(),
                    "game_version": args.game_version,
                    "strings": inputs,
                    "source": str(args.source.resolve()) if args.source else None,
                    "keys_file": fingerprint(args.keys_file.resolve()) if args.keys_file else None,
                    "records": count,
                    "keys": len(keys),
                }
                connection.execute("INSERT INTO metadata VALUES (?)", (json.dumps(info, ensure_ascii=False),))
            if connection.execute("PRAGMA quick_check").fetchone()[0] != "ok":
                raise ValueError("SQLite integrity check failed")
        finally:
            connection.close()
        # Publish only a complete index; preserve the old database on any failure.
        if database.exists() and not args.replace:
            raise ValueError("Database appeared during build; refusing to replace it")
        if database.exists():
            open_index(database).close()
        os.replace(staged, database)
    print_json({"database": str(database), "records": count, "keys": len(keys)})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--strings", type=Path, required=True)
    parser.add_argument("--db", type=Path, required=True)
    parser.add_argument("--temp-root", type=Path, required=True, help="Workspace .tmp directory for build staging")
    parser.add_argument("--source", type=Path, help="Optional readable game Lua tree")
    parser.add_argument("--keys-file", type=Path, help="Optional UTF-8 file, one known key per line")
    parser.add_argument("--game-version", help="Known game version; omitted means unknown")
    parser.add_argument("--replace", action="store_true")
    args = parser.parse_args()
    try:
        build(args)
    except (OSError, ValueError, sqlite3.Error) as error:
        parser.exit(1, f"Error: {error}\n")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
