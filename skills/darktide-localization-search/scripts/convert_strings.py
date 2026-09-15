"""Convert raw DTMT language variants to readable Darktide .strings files."""

import argparse
import json
import re
import struct
import sys
import tempfile
from pathlib import Path

VARIANT_NAME = re.compile(r"(.+)\.(0|[1-9][0-9]*)\.strings\Z")
COUNT = struct.Struct("<I")
ENTRY = struct.Struct("<II")
ESCAPES = str.maketrans({"\\": "\\\\", '"': '\\"', "\t": "\\t", "\r": "\\r", "\n": "\\n"})


def collect_variants(root):
    languages = json.loads(Path(__file__).with_name("languages.json").read_text(encoding="utf-8"))
    groups = {}
    for path in sorted(root.rglob("*.strings")):
        match = VARIANT_NAME.fullmatch(path.name)
        if not match:
            raise ValueError(f"{path}: Expected <resource>.<language-id>.strings")
        if match[2] not in languages:
            raise ValueError(f"{path}: Unknown language ID {match[2]}")
        resource = path.relative_to(root).with_name(match[1] + ".strings")
        groups.setdefault(resource, []).append((int(match[2]), path))
    if not groups:
        raise ValueError("No raw .strings language variants found")
    return groups


def read_variant(path):
    data = path.read_bytes()
    if len(data) < COUNT.size:
        raise ValueError(f"{path}: Missing entry count")
    count = COUNT.unpack_from(data)[0]
    table_end = COUNT.size + count * ENTRY.size
    if table_end > len(data):
        raise ValueError(f"{path}: Truncated entry table")
    # The count is followed by hash/offset pairs; offsets are variant-relative.
    for index in range(count):
        hashed, offset = ENTRY.unpack_from(data, COUNT.size + index * ENTRY.size)
        if not table_end <= offset < len(data):
            raise ValueError(f"{path}: Invalid text offset for {hashed:08X}")
        end = data.find(b"\0", offset)
        if end == -1:
            raise ValueError(f"{path}: Unterminated text for {hashed:08X}")
        try:
            text = data[offset:end].decode("utf-8")
        except UnicodeDecodeError as error:
            raise ValueError(f"{path}: Invalid UTF-8 for {hashed:08X}") from error
        yield hashed, text


def write_resource(variants, destination):
    records = {}
    translations = 0
    duplicates = 0
    for language, path in sorted(variants):
        for hashed, text in read_variant(path):
            values = records.setdefault(hashed, {})
            if language in values:
                duplicates += 1
            # Match DTMT's last-entry-wins map insertion and report duplicates.
            values[language] = text
            translations += 1
    if not records:
        raise ValueError(f"{destination.name}: Resource has no localization records")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("w", encoding="utf-8", newline="\n") as output:
        for hashed, values in sorted(records.items()):
            output.write(f"{hashed:08X} = {{\n")
            for language, text in sorted(values.items()):
                output.write(f'  lang_{language} = "{text.translate(ESCAPES)}"\n')
            output.write("}\n")
    return translations, duplicates


def convert(args):
    root = args.input.resolve(strict=True)
    if not root.is_dir():
        raise ValueError("--input must be a directory")
    output = args.output.resolve()
    if output.exists():
        raise ValueError("Output directory already exists")
    if not output.parent.is_dir():
        raise ValueError("Output parent directory does not exist")
    if root in output.parents:
        raise ValueError("Output must be outside the input directory")
    groups = collect_variants(root)
    translations = 0
    duplicates = 0
    # Stage beside the destination so publication is a same-filesystem rename.
    with tempfile.TemporaryDirectory(prefix="strings-", dir=output.parent) as temporary:
        staged = Path(temporary) / "converted"
        staged.mkdir()
        for resource, variants in sorted(groups.items()):
            count, repeated = write_resource(variants, staged / resource)
            translations += count
            duplicates += repeated
        if output.exists():
            raise ValueError("Output directory appeared during conversion")
        staged.rename(output)
    return {"output": str(output), "resources": len(groups),
            "variants": sum(len(items) for items in groups.values()),
            "translations": translations, "duplicate_entries": duplicates}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, help="Directory of raw DTMT language variants")
    parser.add_argument("--output", type=Path, required=True, help="New directory for readable .strings files")
    args = parser.parse_args()
    try:
        result = convert(args)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Error: {error}\n")
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
