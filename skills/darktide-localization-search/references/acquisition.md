# Data Acquisition

## External Tool

[DTMT](https://git.sclu1034.dev/bitsquid_dt/dtmt) extracts the binary `.strings` resources; the bundled scripts convert them to readable SJSON. Reuse tools located through context, project records or `PATH`. When installation is needed, download the target-platform executable from the most recently published `master` branch build in the official [Packages](https://git.sclu1034.dev/bitsquid_dt/-/packages?q=dtmt&type=generic). Compare publication dates among `master` and `master-<commit>` packages. Select `dtmt.exe` on Windows or `dtmt` on Linux, not the separate `dtmm` mod manager. Keep the tool in the workspace tool directory and record the selected package version.

Some DTMT builds include Oodle statically. If the selected build requires an external Oodle DLL, copy the exact requested DLL from `<game>/binaries` beside the executable, preserving its filename. Game DLLs remain local and are not distributed with the skill. This workflow uses a prebuilt DTMT and does not require Rust or a Lua decompiler.

## Locate And Extract

Resolve the relevant game installation from context or ask if unknown. `<game>/bundle` is the input. Choose separate raw and readable output directories under the task's workspace-local temporary directory.

The localization manager loads these resource names without a file extension:

- `content/localization/ui`
- `content/localization/subtitles`
- `content/localization/items`
- `content/localization/path_of_trust/ui`

The boot loader loads `packages/strings`. Its package hash is `336d896121c7cfaf`, which identifies the localization bundle at `<game>/bundle/336d896121c7cfaf`.

Extract raw `.strings` from that package into an existing empty directory:

```powershell
& '<dtmt-executable>' bundle extract -i '*.strings' '<game>/bundle/336d896121c7cfaf' '<raw-directory>'
```

Omit `-d`: conversion is handled by the bundled scripts. Raw filenames include the language ID, such as `<resource>.1024.strings`; the resource may be a hash or a dictionary-resolved path. An external filename or key-name dictionary is not required.

DTMT can log individual bundle or file failures while returning success; check those messages and the expected resources before treating an extraction as complete.

## Convert And Index

Use Python 3.10 or later, or Windows PowerShell 5.1 / PowerShell 7. Conversion needs only their built-in libraries; SQLite is needed only for indexing and querying. `<scripts>` is this skill's `scripts` directory. The readable output directory must not exist, and its parent must already exist.

```powershell
python -B '<scripts>/convert_strings.py' --input '<raw-directory>' --output '<strings-directory>'
```

Equivalent independent PowerShell invocation:

```powershell
& '<scripts>/convert_strings.ps1' -InputDirectory '<raw-directory>' -OutputDirectory '<strings-directory>'
```

The converters combine language variants into one readable `.strings` file per resource, preserving hashes, text and resource-relative paths. Repeated hashes within a language follow DTMT's last-entry-wins behavior and are counted in `duplicate_entries`. Invalid binary data fails without publishing a partial output directory. The indexer accepts these SJSON files, not the raw binary files.

Publish the validated files to the chosen persistent localization directory before following [Build And Query](querying.md), so index provenance points to retained inputs rather than temporary paths. Keep the previous dataset until the replacement is validated; do not merge extraction generations. Apply the temporary-directory cleanup described in the skill entrypoint.
