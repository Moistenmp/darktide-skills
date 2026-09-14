# Source Acquisition

## Workspace Layout

Keep tools acquired for this workflow, generated source trees, and acquisition/build intermediates inside the active workspace. Reuse suitable existing workspace locations without moving them; otherwise use:

- `<workspace>/tools/<tool>/<release-or-commit>/` for downloaded tools and their build sources.
- `<workspace>/game-data/source/` for readable game Lua, whether decompiled locally or cloned.
- `<workspace>/.tmp/<task-id>/` for downloads awaiting unpacking, compiler intermediates, bytecode, and unvalidated source output.

Resolve these write destinations, including directory links, before use; they must remain inside the workspace. Existing tools and input data elsewhere can be used in place. The game installation is an input, not an extraction destination. Pass explicit output paths rather than leaving a tool's default `out` directory in its working directory.

Create intermediate directories only when needed. On success or failure, remove this run's acquisition/build intermediates, then remove `.tmp` non-recursively if empty. Retain failed-step intermediates only when needed to diagnose or resume that step, and report their location and reason for retention. Leave other runs' files untouched.

## External Tools

- [limn releases](https://github.com/manshanko/limn/releases): extract Darktide bundles.
- [LuaJIT Decompiler v2 — Aussiemon's fork](https://github.com/Aussiemon/luajit-decompiler-v2): includes Fatshark-specific bytecode support. Reuse an executable built from this fork, or build it from source.

Reuse tools located through user/context paths, project records, or `PATH`. Keep new tool packages in the workspace's tool directory, separate from the skill and game data, and retain the selected release or commit identity. Existing suitable installations need not be moved or upgraded.

The commands below use PowerShell and Windows executables. On Linux, limn requires Wine because it loads the game's decompression library; the Windows decompiler also needs an appropriate execution environment.

## Build The Decompiler When Needed

If no suitable executable is available, clone Aussiemon's fork into `<decompiler-source>` under the tool directory. The repository does not include a build project. Use an x64 Visual Studio Developer PowerShell with MSVC C++ tools and the Windows SDK, and choose `<task-temp>/decompiler-build` as `<build-directory>`.

The source requires C++20 and `/J` (unsigned plain `char`). Compile its five translation units directly; `user32.lib` and `comdlg32.lib` supply the Windows UI functions, while the source already links `shlwapi.lib`:

```powershell
$decompilerSource = (Resolve-Path -LiteralPath '<decompiler-source>').Path
$buildDirectory = '<build-directory>'
New-Item -ItemType Directory -Path $buildDirectory | Out-Null
Push-Location -LiteralPath $buildDirectory
try {
    $sources = @('main.cpp', 'ast/ast.cpp', 'bytecode/bytecode.cpp', 'bytecode/prototype.cpp', 'lua/lua.cpp') | ForEach-Object { Join-Path $decompilerSource $_ }
    & cl.exe /nologo /std:c++20 /J /EHsc /O2 /MT @sources /Fe:luajit-decompiler-v2.exe /link user32.lib comdlg32.lib
    if ($LASTEXITCODE -ne 0) { throw 'Decompiler build failed' }
    & .\luajit-decompiler-v2.exe '-?'
    if ($LASTEXITCODE -ne 0) { throw 'Decompiler help check failed' }
} finally {
    Pop-Location
}
```

The executable is `<build-directory>/luajit-decompiler-v2.exe`; the `-?` invocation checks that it starts and displays its options. After that check, copy the executable into the selected tool directory before cleaning the build directory.

## Extract And Decompile

Identify the relevant Darktide game directory from context, or ask if unknown; do not scan entire drives. Use `<game>/bundle` as input. Choose separate, empty bytecode and source output directories under the task's temporary directory; generate and validate a refresh there before publishing it to the chosen persistent source location. Preserve any existing repository metadata and unrelated files when updating a source tree.

Darktide stores Lua as LuaJIT bytecode. In its normal Lua extraction mode, limn repairs the bytecode header and uses the embedded resource path for output; an external filename dictionary is not required.

For Oodle decompression, limn needs the game's `oo2core_*_win64.dll`; the decompiler does not. Current limn tries `oo2core_9_win64.dll`, then `oo2core_8_win64.dll`, and can load it from `<game>/binaries` when given `<game>/bundle`. If loading fails, prepare a workspace-local limn installation with the requested DLL from that game directory beside `limn.exe`, preserving its filename. Keep this game dependency local; do not distribute it with the skill.

Extract bytecode:

```powershell
& '<limn-executable>' -i '<game>/bundle' -o '<bytecode-directory>' lua
```

After successful extraction, create the empty source output directory and decompile:

```powershell
& '<decompiler-executable>' '<bytecode-directory>' -e lua -o '<source-directory>' -s
```

`-s` suppresses assertion dialogs but also skips files that fail to decompile. The process can return zero despite skipped files: read its failure summary and compare input/output relative `.lua` paths before calling the result complete. Keep any missing files explicit when querying partial output. Check the installed tools' `--help` / `-?` for version-specific options.

### Optional Git Snapshots

When Git is available, record local snapshots after successful source decompilation or refresh. Reuse the repository that already owns the source location, or initialize one there if none exists. Commit only changed, validated Lua source in its persistent location; leave unrelated changes untouched and skip empty commits. Keep tools and intermediates, including extracted bytecode, out of these snapshots. Snapshotting is optional: if Git is unavailable or a snapshot cannot be completed, report that and continue with the validated source. Do not push automatically.

## Clone Source

Use the user's chosen repository, or [Aussiemon/Darktide-Source-Code](https://github.com/Aussiemon/Darktide-Source-Code), a community-maintained decompiled source tree. Clone into the chosen source location, separate from tool installations. The repository's README records game patches; select a matching revision from its existing history when the task targets a particular build rather than assuming the default branch matches the installed game.
