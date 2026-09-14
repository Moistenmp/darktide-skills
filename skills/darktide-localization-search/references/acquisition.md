# Data Acquisition

## External Tool

[DTMT](https://git.sclu1034.dev/bitsquid_dt/dtmt) is an external dependency, not bundled with this skill. Its [releases](https://git.sclu1034.dev/bitsquid_dt/dtmt/releases/) provide the extractor that converts binary `.strings` resources into the SJSON consumed by the indexer. Reuse an appropriate executable located through context, project records or `PATH`. Put new installations in the workspace's tool directory and record the selected release identity.

The Windows build uses the game's Oodle decompression DLL. The current DTMT build links `oo2core_9_win64.dll`; if needed, prepare a workspace-local DTMT installation with that file from the relevant `<game>/binaries` beside `dtmt.exe`. Match the selected tool's actual dependency; do not rename a different DLL version. Keep the game DLL local, not in the published skill. Extracting `.strings` does not require a Lua decompiler or building Rust when a suitable DTMT binary is available.

## Locate And Extract

Resolve the relevant game installation from context or ask if unknown. `<game>/bundle` is the input. Choose an empty `<strings-directory>` under the task's workspace-local temporary directory and pass it explicitly to DTMT.

The localization manager loads these resource names without a file extension:

- `content/localization/ui`
- `content/localization/subtitles`
- `content/localization/items`
- `content/localization/path_of_trust/ui`

The boot loader loads `packages/strings`. Its package hash is `336d896121c7cfaf`, which identifies the localization bundle at `<game>/bundle/336d896121c7cfaf`.

Extract `.strings` from that package into an existing empty directory:

```powershell
& '<dtmt-executable>' bundle extract -d -i '*.strings' '<game>/bundle/336d896121c7cfaf' '<strings-directory>'
```

`-d` converts the binary resources to readable SJSON. DTMT can emit a hash filename or a resource-relative path depending on its filename dictionary; the indexer searches recursively and preserves the relative path. An external key-name dictionary is not required for translation queries.

DTMT can log individual bundle or file failures while returning success; check those messages and the expected output files before treating an extraction as complete. The indexer accepts readable DTMT output, not raw binary `.strings` files.

Publish the validated files to the chosen persistent localization directory before indexing, so index provenance points to retained inputs rather than temporary paths. Keep the previous dataset until the replacement is validated; do not merge extraction generations. Apply the temporary-directory cleanup described in the skill entrypoint.
