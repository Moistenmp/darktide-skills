# Build And Query

## Dependencies

- **Preferred:** Python 3.10 or later with its standard-library `sqlite3` module. A normal official Python installation includes it; check both requirements with `python -c "import sys, sqlite3; sys.exit(sys.version_info < (3, 10))"`. No pip packages, separate SQLite executable or database service are required.
- **Windows alternative:** Windows PowerShell 5.1 or PowerShell 7, plus `sqlite3.exe` from the official [SQLite download page](https://www.sqlite.org/download.html). Choose the Windows **tools** ZIP for the machine architecture, not the DLL ZIP. Extract it into the project's tool directory and pass its path with `-Sqlite` if it is not on `PATH`. No Python, NuGet package or third-party PowerShell module is used. PowerShell's built-in `Add-Type` compiles the embedded streaming-parser and integer-hashing helper.

The following examples use placeholder paths and values. `<scripts>` means this skill's `scripts` directory; the database's parent directory must already exist. Use the workspace locations from the skill entrypoint. Python's `-B` avoids writing import caches into the installed skill.

## Build

```powershell
python -B '<scripts>/build_index.py' --strings '<strings-directory>' --db '<index-directory>/localization.sqlite' --temp-root '<workspace>/.tmp' --source '<game-lua-root>'
```

Equivalent independent PowerShell invocation:

```powershell
& '<scripts>/build_index.ps1' -Strings '<strings-directory>' -Database '<index-directory>/localization.sqlite' -TempRoot '<workspace>/.tmp' -Source '<game-lua-root>' -Sqlite '<sqlite-executable>'
```

`--source` / `-Source` is optional; it scans `.lua` files recursively for static `loc_...` candidates. `--keys-file` / `-KeysFile` optionally adds known names from a UTF-8 file containing one key per line. Named records in `.strings` also supply key names. Neither optional input is needed to query a supplied key or search translations.

`--temp-root` / `-TempRoot` is required. Pass the workspace's `.tmp` directory; its parent must exist. The builder creates a unique `localization-<id>` child, removes that child on success or failure, and removes the root only if empty. The temporary root and database must be on the same filesystem for atomic publication. These arguments are explicit paths; the caller must resolve them within the active workspace before invocation.

Use `--game-version` / `-GameVersion` only for a known version. Use `--replace` / `-Replace` to rebuild an existing index from this skill. Each build creates a separate database and replaces the target only after successful import and an integrity check. Refreshes need the desired key inputs again; the old index is not merged into the new one. The SQLite index is rebuildable and is not part of source Git snapshots by default.

## Query

```powershell
python -B '<scripts>/query.py' --db '<index-directory>/localization.sqlite' --key '<localization-key>' --languages en zh-cn
python -B '<scripts>/query.py' --db '<index-directory>/localization.sqlite' --text 'zh-cn=<Chinese text>' --text 'en=<English text>' --languages en zh-cn
```

Equivalent PowerShell queries:

```powershell
& '<scripts>/query.ps1' -Database '<index-directory>/localization.sqlite' -Key '<localization-key>' -Languages en,zh-cn -Sqlite '<sqlite-executable>'
& '<scripts>/query.ps1' -Database '<index-directory>/localization.sqlite' -Text 'zh-cn=<Chinese text>','en=<English text>' -Languages en,zh-cn -Sqlite '<sqlite-executable>'
```

- Repeat `--key` or `--hash` for batch lookup; PowerShell accepts arrays with `-Key` and `-Hash`. Hashes are eight hexadecimal digits. Keys and hashes form one OR selection; additional text filters narrow that selection.
- Each `--text LANGUAGE=TEXT` / `-Text 'LANGUAGE=TEXT'` is a case-sensitive, literal substring condition. Repeated conditions are ANDed, including conditions in different languages. `*=TEXT` searches any player language; `comment=TEXT` searches annotations. Quotes, `%` and `_` are literal text, not SQL syntax or wildcards.
- Every result includes `resource`, `hash`, all known `keys`, `comment`, and the requested `translations`. Text search therefore also performs reverse lookup. `--resource` / `-Resource` restricts results to one exact returned resource path.
- UTF-8 JSON output includes `total`, `offset`, `limit`, and `matches`. The default limit is 50 records. Use `--limit 0` / `-Limit 0` for all results or `--offset` / `-Offset` to page. An empty match set is a successful query, not a script failure.
- Use `--info` / `-Info` with the database path to inspect provenance instead of running a query. Queries open the database read-only.
