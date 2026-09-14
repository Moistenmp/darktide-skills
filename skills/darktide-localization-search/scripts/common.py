"""Shared data-format and SQLite helpers for localization scripts."""

import hashlib
import json
import re
import sqlite3
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
LANGUAGES = json.loads((SCRIPTS / "languages.json").read_text(encoding="utf-8"))
CODES = list(LANGUAGES.values())
APPLICATION_ID = 1146375251
SCHEMA_VERSION = 1
HASH_CHUNK_SIZE = 1024 * 1024
KEY_PATTERN = re.compile(r"(?<![A-Za-z0-9_])loc_[A-Za-z0-9_]+")
HEADER = re.compile(r'^(.*?) = \{$')
FIELD = re.compile(r'^  lang_([0-9]+) = (.*)$')
HEX_HASH = re.compile(r"[0-9A-Fa-f]{8}\Z")
ESCAPES = {"t": "\t", "n": "\n", "r": "\r", '"': '"', "\\": "\\"}
MASK64 = (1 << 64) - 1
MURMUR_MIX = 0xC6A4A7935BD1E995


def key_hash(key):
    """Fatshark uses the high 32 bits of seed-zero MurmurHash64A."""
    data = key.encode("utf-8")
    value = len(data) * MURMUR_MIX & MASK64
    stop = len(data) - len(data) % 8
    for position in range(0, stop, 8):
        block = int.from_bytes(data[position:position + 8], "little")
        block = block * MURMUR_MIX & MASK64
        block ^= block >> 47
        block = block * MURMUR_MIX & MASK64
        value = (value ^ block) * MURMUR_MIX & MASK64
    if stop < len(data):
        value ^= int.from_bytes(data[stop:], "little")
        value = value * MURMUR_MIX & MASK64
    value ^= value >> 47
    value = value * MURMUR_MIX & MASK64
    value ^= value >> 47
    return f"{value >> 32:08X}"


def decode_string(raw):
    if not raw.startswith('"'):
        if not raw or re.search(r"[ \t\r\n=\"'\\:]", raw):
            raise ValueError("Invalid unquoted SJSON string")
        return raw
    if len(raw) < 2 or not raw.endswith('"'):
        raise ValueError("Unterminated SJSON string")
    body = raw[1:-1]
    # The extractor escapes only these five characters, not JSON's full grammar.
    if re.search(r'(?<!\\)(?:\\\\)*"', body):
        raise ValueError("Unescaped quote in SJSON string")

    def unescape(match):
        character = match[0][1:]
        if character not in ESCAPES:
            raise ValueError("Invalid SJSON escape")
        return ESCAPES[character]

    return re.sub(r"\\[\s\S]?", unescape, body)


def read_records(path):
    values = None
    with path.open(encoding="utf-8-sig", newline="") as source:
        for number, line in enumerate(source, 1):
            line = line.rstrip("\r\n")
            if not line:
                continue
            try:
                if values is None:
                    header = HEADER.fullmatch(line)
                    if not header:
                        raise ValueError("Expected a record header")
                    name = decode_string(header[1])
                    hashed = name.upper() if HEX_HASH.fullmatch(name) else key_hash(name)
                    values = {}
                elif line == "}":
                    if not values:
                        raise ValueError("Record has no language fields")
                    yield hashed, name, values
                    values = None
                else:
                    field = FIELD.fullmatch(line)
                    if not field or field[1] not in LANGUAGES:
                        raise ValueError("Unknown language or invalid field")
                    code = LANGUAGES[field[1]]
                    if code in values:
                        raise ValueError("Duplicate language field")
                    values[code] = decode_string(field[2])
            except ValueError as error:
                raise ValueError(f"{path}:{number}: {error}") from error
    if values is not None:
        raise ValueError(f"{path}: Unterminated record")


def source_keys(source, keys_file):
    keys = set()
    if source:
        paths = sorted(source.rglob("*.lua"))
        if not paths:
            raise ValueError("Source directory contains no .lua files")
        for path in paths:
            keys.update(KEY_PATTERN.findall(path.read_text(encoding="utf-8-sig")))
    if keys_file:
        for line in keys_file.read_text(encoding="utf-8-sig").split("\n"):
            key = line.strip()
            if key:
                keys.add(key)
    return keys


def fingerprint(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(HASH_CHUNK_SIZE):
            digest.update(chunk)
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": digest.hexdigest()}


def open_index(path):
    connection = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)
    try:
        identity = connection.execute("PRAGMA application_id").fetchone()[0]
        version = connection.execute("PRAGMA user_version").fetchone()[0]
        if (identity, version) != (APPLICATION_ID, SCHEMA_VERSION):
            raise ValueError("Not a localization index created by this skill; build a separate index")
    except Exception:
        connection.close()
        raise
    return connection


def columns_sql():
    return ", ".join(f'"{code}" TEXT' for code in CODES)


def print_json(value):
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))
