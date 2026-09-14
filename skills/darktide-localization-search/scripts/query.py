"""Query keys, hashes or literal text and return translations and reverse candidates."""

import argparse
import json
import sqlite3
import sys
from pathlib import Path

from common import CODES, HEX_HASH, SCRIPTS, key_hash, open_index, print_json


def query(args):
    connection = open_index(args.db)
    try:
        if args.info:
            print_json(json.loads(connection.execute("SELECT info FROM metadata").fetchone()[0]))
            return
        languages = args.languages or [code for code in CODES if code != "comment"]
        if any(code not in CODES or code == "comment" for code in languages):
            raise ValueError("Unknown output language; comment is returned separately")
        if args.limit < 0 or args.offset < 0:
            raise ValueError("Limit and offset must be nonnegative")
        if any(not HEX_HASH.fullmatch(value) for value in args.hash):
            raise ValueError("Hashes must contain exactly eight hexadecimal digits")
        if any(not value for value in args.key):
            raise ValueError("Keys must not be empty")
        hashes = sorted({value.upper() for value in args.hash} | {key_hash(key) for key in args.key})
        parameters = {"limit": args.limit, "take": args.limit or -1, "offset": args.offset}
        filters = []
        if hashes:
            parameters["hashes"] = json.dumps(hashes)
            filters.append("hash IN (SELECT value FROM json_each(@hashes))")
        for index, text in enumerate(args.text):
            code, separator, value = text.partition("=")
            if not separator or not value or (code not in CODES and code != "*"):
                raise ValueError("Text filters must be LANGUAGE=TEXT, or *=TEXT; text must not be empty")
            fields = [c for c in CODES if c != "comment"] if code == "*" else [code]
            parameter = f"text{index}"
            parameters[parameter] = value
            filters.append("(" + " OR ".join(f'instr("{c}", @{parameter}) > 0' for c in fields) + ")")
        if args.resource is not None:
            parameters["resource"] = args.resource
            filters.append("resource = @resource")
        if not (hashes or args.text):
            raise ValueError("Supply at least one --key, --hash or --text filter")
        translations = ", ".join(f"'{code}', \"{code}\"" for code in dict.fromkeys(languages))
        sql = (SCRIPTS / "query.sql").read_text(encoding="utf-8")
        sql = sql.replace("/*FILTERS*/", " AND ".join(filters)).replace("/*TRANSLATIONS*/", translations)
        print(connection.execute(sql, parameters).fetchone()[0])
    finally:
        connection.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, required=True)
    parser.add_argument("--key", action="append", default=[])
    parser.add_argument("--hash", action="append", default=[])
    parser.add_argument("--text", action="append", default=[], help="LANGUAGE=TEXT; repeat for AND")
    parser.add_argument("--languages", nargs="+", help="Output languages, default: all")
    parser.add_argument("--resource", help="Exact resource path returned by a prior query")
    parser.add_argument("--limit", type=int, default=50, help="Maximum returned records; 0 means all")
    parser.add_argument("--offset", type=int, default=0)
    parser.add_argument("--info", action="store_true", help="Show index provenance instead of querying")
    args = parser.parse_args()
    try:
        query(args)
    except (OSError, ValueError, sqlite3.Error) as error:
        parser.exit(1, f"Error: {error}\n")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
