# Workspace And Tools

## Paths

Reuse suitable existing workspace locations; otherwise use:

- `<workspace>/tools/<tool>/<release-or-commit>/` for acquired tools, external scripts, dictionaries, and dependencies.
- `<workspace>/game-data/resources/` for retained resources, preserving resource-relative paths.
- `<workspace>/.tmp/<task-id>/` for acquisition and conversion intermediates.

Resolve write destinations, including directory links, inside the active workspace. Existing tools and inputs elsewhere can be used in place. The game installation is an input, not an output destination. Supply explicit output paths instead of accepting a tool's default working-directory output.

Whether a file is intermediate depends on the requested result: DDS is retained when requested, but is intermediate when only PNG is needed. Clean this run's deterministic intermediates on success or failure; remove `.tmp` non-recursively when empty. Keep failed-step files only when needed to diagnose or resume, reporting where and why; leave other runs' files untouched.

## Tool Selection

Reuse tools found through context, project records, or `PATH`. Acquire only missing tools needed for the selected operation, using the workspace tool directory and recording the selected release or commit.

### Required For Bundle Extraction

Use [limn](https://github.com/manshanko/limn/releases) 0.7.1 or later with the game's Oodle DLL for bundle extraction, including DDS, OGG, and JSON output.

Current limn builds try `oo2core_9_win64.dll`, then `oo2core_8_win64.dll`; supplying `<game>/bundle` allows discovery of the sibling `binaries` directory. If necessary, copy the matching DLL from that game's `binaries` beside the workspace-local executable, preserving its filename. Game DLLs stay local, not in the published skill.

The examples use Windows tools. On Linux, limn needs Wine to load the game's Windows decompression library.

### Optional — Select By Operation

- **Image-format conversion:** [DirectXTex](https://github.com/microsoft/DirectXTex/releases) provides `texconv`, for example when PNG is required instead of DDS.
- **WAV decoding:** [vgmstream](https://github.com/vgmstream/vgmstream/releases) provides the CLI decoder for existing OGG or WEM; retain its accompanying libraries. Keeping OGG as the final output does not need it.
- **Embedded event audio:** [QuickBMS](https://aluigi.altervista.org/quickbms.htm) with [AlphaTwentyThree's wavescan.bms, distributed by Wwise-Unpacker](https://github.com/Vextil/Wwise-Unpacker/blob/master/Tools/wavescan.bms) scans media embedded in event resources. An existing suitable `wav_scanner.bms` can also be used; output extensions differ between script versions.
- **Bundle lookup and inspection:** [DTMT](https://git.sclu1034.dev/bitsquid_dt/dtmt) locates resources through the game's existing bundle database and lists bundle contents. When installation is needed, download the target-platform executable from the most recently published `master` branch build in the official [Packages](https://git.sclu1034.dev/bitsquid_dt/-/packages?q=dtmt&type=generic), comparing publication dates among `master` and `master-<commit>` packages. Select `dtmt.exe` on Windows or `dtmt` on Linux, not the separate `dtmm` mod manager, and record the selected package version. Oodle may be statically included; copy the exact requested game DLL beside the executable only if required. DTMT uses a CSV dictionary, unlike limn's plain-text dictionary; hash-based inspection does not require known names.

  ```powershell
  & '<dtmt-executable>' bundle db find-file '<game>/bundle/bundle_database.data' '<resource-name-or-hash>'
  & '<dtmt-executable>' bundle list '<game>/bundle/<bundle-hash>'
  ```

  A resource may appear in several bundles, including entries without payload data.

- **Model-related resources:** For resources such as `bones` and `material`, see [Bitsquid Blender Tools](https://gitlab.com/qasikfwn/bitsquid-blender-tools) and its current Blender import support.
