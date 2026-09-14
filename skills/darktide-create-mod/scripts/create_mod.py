#!/usr/bin/env python3

import argparse
import json
import re
import shutil
import sys
from pathlib import Path
from urllib.parse import urlparse


VALID_MOD_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a Darktide mod from the bundled templates."
    )
    parser.add_argument("--output-root", required=True, type=Path)
    parser.add_argument("--name", required=True)
    parser.add_argument("--author", required=True)
    parser.add_argument("--title")
    parser.add_argument("--description", required=True)
    parser.add_argument("--version", default="1.0.0")
    parser.add_argument("--homepage")
    parser.add_argument("--source")
    parser.add_argument(
        "--funding", action="append", default=[], metavar="PROVIDER=URL"
    )
    parser.add_argument("--required-dependency", action="append", default=[])
    parser.add_argument("--load-after", action="append", default=[])
    parser.add_argument("--load-before", action="append", default=[])
    parser.add_argument(
        "--localized-name", action="append", default=[], metavar="LANGUAGE=TEXT"
    )
    parser.add_argument(
        "--localized-description",
        action="append",
        default=[],
        metavar="LANGUAGE=TEXT",
    )
    return parser.parse_args()


def derive_title(name: str) -> str:
    value = re.sub(r"[_-]+", " ", name)
    value = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", value)
    value = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", " ", value)
    words = value.split()
    return " ".join(
        word if word.isupper() else word[:1].upper() + word[1:] for word in words
    )


def lua_string(value: str) -> str:
    escapes = {
        "\\": "\\\\",
        '"': '\\"',
        "\n": "\\n",
        "\r": "\\r",
        "\t": "\\t",
    }
    encoded = []

    for character in value:
        if character in escapes:
            encoded.append(escapes[character])
        elif ord(character) < 32 or ord(character) == 127:
            encoded.append(f"\\{ord(character):03d}")
        else:
            encoded.append(character)

    return f'"{"".join(encoded)}"'


def validate_url(label: str, value: str | None) -> str | None:
    if value is None:
        return None

    parsed = urlparse(value)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ValueError(f"{label} must be an HTTP or HTTPS URL")
    return value


def parse_funding(entries: list[str]) -> dict[str, str]:
    funding = {}

    for entry in entries:
        provider, separator, url = entry.partition("=")
        provider = provider.strip()
        url = url.strip()

        if not separator or not provider or not url:
            raise ValueError("Funding entries must use PROVIDER=URL")
        if provider in funding:
            raise ValueError(f'Duplicate funding provider: "{provider}"')

        funding[provider] = validate_url(f'Funding URL for "{provider}"', url)

    return funding


def validate_dependencies(label: str, values: list[str]) -> list[str]:
    result = []

    for value in values:
        if VALID_MOD_NAME.fullmatch(value) is None:
            raise ValueError(f'Invalid {label} dependency: "{value}"')
        if value not in result:
            result.append(value)

    return result


def load_language_config(skill_root: Path) -> tuple[str, tuple[str, ...]]:
    config_path = skill_root / "references" / "languages.json"

    if not config_path.is_file():
        raise FileNotFoundError(f"Bundled language list is missing: {config_path}")

    config = json.loads(config_path.read_text(encoding="utf-8"))
    if not isinstance(config, dict):
        raise ValueError("Bundled language list must contain a JSON object")

    primary = config.get("primary")
    if not isinstance(primary, str) or not primary.strip():
        raise ValueError(
            "Bundled language list must define a non-empty primary language"
        )

    languages = config.get("languages")
    if not isinstance(languages, dict) or not languages:
        raise ValueError(
            "Bundled language list must define a non-empty languages object"
        )

    for code, display_name in languages.items():
        if not isinstance(code, str) or VALID_MOD_NAME.fullmatch(code) is None:
            raise ValueError(f'Invalid language code in bundled language list: "{code}"')
        if not isinstance(display_name, str) or not display_name.strip():
            raise ValueError(f'Language "{code}" must have a non-empty English name')

    if primary not in languages:
        raise ValueError(
            f'Primary language "{primary}" is not in bundled language list'
        )

    return primary, tuple(languages)


def parse_localizations(
    label: str,
    entries: list[str],
    supported_languages: tuple[str, ...],
    primary_language: str,
) -> dict[str, str]:
    localizations = {}

    for entry in entries:
        language, separator, text = entry.partition("=")
        language = language.strip()

        if not separator or not language or not text.strip():
            raise ValueError(f"{label} entries must use LANGUAGE=TEXT")
        if VALID_MOD_NAME.fullmatch(language) is None:
            raise ValueError(f'Invalid localization language: "{language}"')
        if language not in supported_languages:
            expected = ", ".join(supported_languages)
            raise ValueError(
                f'Unsupported localization language: "{language}". '
                f"Expected one of: {expected}"
            )
        if language == primary_language:
            raise ValueError(
                f'{label} must not override the primary "{primary_language}" value'
            )
        if language in localizations:
            raise ValueError(f'Duplicate {label} language: "{language}"')

        localizations[language] = text

    return localizations


def lua_localization_entries(values: dict[str, str]) -> str:
    return "\n".join(
        f"\t\t[{lua_string(language)}] = {lua_string(text)},"
        for language, text in values.items()
    )


def replace_tokens(value: str, replacements: tuple[tuple[str, str], ...]) -> str:
    replacement_map = dict(replacements)
    tokens = sorted(replacement_map, key=len, reverse=True)
    if not tokens:
        return value

    token_pattern = re.compile("|".join(re.escape(token) for token in tokens))
    return token_pattern.sub(
        lambda match: replacement_map.get(match.group(0), match.group(0)), value
    )


def render_template(
    template_root: Path,
    target: Path,
    common_replacements: tuple[tuple[str, str], ...],
    file_replacements: dict[str, tuple[tuple[str, str], ...]],
    optional_metadata: dict[str, object],
) -> None:
    target.mkdir()

    try:
        for source in sorted(template_root.rglob("*")):
            relative = source.relative_to(template_root)
            rendered_parts = [
                replace_tokens(part, common_replacements) for part in relative.parts
            ]
            destination = target.joinpath(*rendered_parts)

            if source.is_dir():
                destination.mkdir(parents=True, exist_ok=True)
                continue

            destination.parent.mkdir(parents=True, exist_ok=True)
            content = source.read_text(encoding="utf-8")
            replacements = common_replacements + file_replacements.get(
                relative.as_posix(), ()
            )
            rendered = replace_tokens(content, replacements)
            destination.write_text(rendered, encoding="utf-8")

        info_path = target / "info.json"
        info = json.loads(info_path.read_text(encoding="utf-8"))
        info.update(optional_metadata)
        info_path.write_text(
            json.dumps(info, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    except Exception:
        shutil.rmtree(target)
        raise


def main() -> int:
    args = parse_args()
    output_root = args.output_root.resolve()

    if not output_root.is_dir():
        raise NotADirectoryError(f"Output root does not exist: {output_root}")
    if VALID_MOD_NAME.fullmatch(args.name) is None:
        raise ValueError(
            f'Mod name "{args.name}" must match [A-Za-z0-9][A-Za-z0-9_-]*'
        )
    if not args.author.strip():
        raise ValueError("Author must not be empty")
    if not args.description.strip():
        raise ValueError("Description must not be empty")
    if args.title is not None and not args.title.strip():
        raise ValueError("Title must not be empty when supplied")
    if not args.version.strip():
        raise ValueError("Version must not be empty")

    title = args.title or derive_title(args.name)
    target = output_root / args.name

    if target.exists():
        raise FileExistsError(f'Target folder already exists: "{target}"')

    skill_root = Path(__file__).resolve().parent.parent
    template_root = skill_root / "assets" / "mod-template"

    if not template_root.is_dir():
        raise NotADirectoryError(f"Bundled template is missing: {template_root}")

    primary_language, supported_languages = load_language_config(skill_root)

    optional_metadata = {}
    homepage = validate_url("Homepage", args.homepage)
    source = validate_url("Source", args.source)
    funding = parse_funding(args.funding)
    required = validate_dependencies("required", args.required_dependency)
    self_after = validate_dependencies("load-after", args.load_after)
    self_before = validate_dependencies("load-before", args.load_before)
    localized_names = parse_localizations(
        "Localized name",
        args.localized_name,
        supported_languages,
        primary_language,
    )
    localized_descriptions = parse_localizations(
        "Localized description",
        args.localized_description,
        supported_languages,
        primary_language,
    )

    if homepage:
        optional_metadata["homepage"] = homepage
    if source:
        optional_metadata["source"] = source
    if funding:
        optional_metadata["funding"] = funding

    dependencies = {}
    if required:
        dependencies["required"] = required
    if self_after:
        dependencies["self_after"] = self_after
    if self_before:
        dependencies["self_before"] = self_before
    if dependencies:
        optional_metadata["dependencies"] = dependencies

    localizations = {}
    languages = dict.fromkeys([*localized_names, *localized_descriptions])
    for language in languages:
        localized_fields = {}
        if language in localized_names:
            localized_fields["name"] = localized_names[language]
        if language in localized_descriptions:
            localized_fields["description"] = localized_descriptions[language]
        localizations[language] = localized_fields
    if localizations:
        optional_metadata["localization"] = localizations

    common_replacements = (("%%name", args.name),)
    file_replacements = {
        "info.json": (
            ("%%title", json.dumps(title, ensure_ascii=False)[1:-1]),
            (
                "%%description",
                json.dumps(args.description, ensure_ascii=False)[1:-1],
            ),
            ("%%version", json.dumps(args.version, ensure_ascii=False)[1:-1]),
            ("%%author", json.dumps(args.author, ensure_ascii=False)[1:-1]),
        ),
        "scripts/mods/%%name/%%name_localization.lua": (
            ("%%title", lua_string(title)[1:-1]),
            ("%%description", lua_string(args.description)[1:-1]),
            ("%%localized_names", lua_localization_entries(localized_names)),
            (
                "%%localized_descriptions",
                lua_localization_entries(localized_descriptions),
            ),
        ),
    }
    render_template(
        template_root,
        target,
        common_replacements,
        file_replacements,
        optional_metadata,
    )
    print(target)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (
        FileExistsError,
        FileNotFoundError,
        NotADirectoryError,
        ValueError,
    ) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
