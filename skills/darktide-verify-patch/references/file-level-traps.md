# File-level traps — the thing you edited is not the thing that runs

> Companion to `../SKILL.md`. The copy-semantics rule in `copy-semantics.md` says: when a value
> is copied at module load and the runtime reads the copy, **patch the copy**. The same rule
> applies one level up — to files. All three traps below share the identical shape:
> **something succeeds, nothing is reported, and what runs is not what you changed.**

## Trap 1 — editing a file the mod does not load

A mod's `.mod` descriptor names the script it executes:

```text
<game>/mods/<mod-id>/<mod-id>.mod   ->  mod_script = "scripts/mods/<mod-id>/<mod-id>"
```

A mod folder can contain **other loose `.lua` files at its top level** — older revisions, left
behind by a refactor, or a copy someone kept while working. They look like the mod's source.
**Editing the visible file changes nothing**, and produces no error and no log line, because
that file is never opened.

**Check before editing:** open the `.mod` descriptor and confirm the `mod_script` path resolves
to the file you are about to change. Then confirm you are editing that file and not a
similarly-named sibling.

**Symptom:** the same value behaves identically before and after your edit; the log shows no
change in behavior at all.

## Trap 2 — a byte-order mark makes a comment parse as content

DML reads `mod_load_order.txt` line by line and ignores blank lines and lines beginning with
`--`. A UTF-8 BOM (`EF BB BF`) placed before line 1 **becomes part of the first line's content**,
so the comment banner no longer begins with `--`.

The result is not a parse failure. DML **accepts the comment text as a mod name** and tries to
open it:

```text
[Mod] Error opening './../mods/ -- ####..../ -- ####....mod'
Mod file is invalid or missing. Mod " -- ####...." with id 2 skipped.
```

**The signature is selective per-line failure.** Other mods load normally — only the entry
carrying the BOM-derived text fails, and the "mod name" in the message is a line of your own
comment. Read the quoted name back against your file: if it looks like prose, this is the cause.

**Fix:** rewrite the file without a BOM. Verify the first three bytes are not `EF BB BF`, and
prefer a byte-level tool over an editor round-trip — Windows PowerShell 5.1's
`Set-Content -Encoding UTF8` **adds a BOM**, so a "read the file and write it back" cycle can
introduce this defect rather than repair it.

## Trap 3 — missing metadata fails silently, per mod

`info.json` is the canonical metadata source DMF reads for each mod. A missing or unparseable
`info.json` is **not an error**: the reader returns an empty table and continues.

Consequences worth internalising:

- **Most mods do not have one.** In a typical install the majority of mod directories have no
  top-level `info.json` at all. Absence is normal, not a fault.
- **Display names come from a fallback chain**, and only the last resort is the directory name:
  `info.json.localization["<locale>"].name` → `info.json.name` → a quoted token inside an
  assertion message → the directory name.
- **The key is the directory name.** `info.json` carries no `id` field. Any lookup keyed on a
  field named `id` returns zero rows — silently, because a missing key in an empty table is
  just `nil`.

⇒ **If a display name looks wrong, that is a metadata question, not a loading question.** A mod
can be fully loaded and working with a name DML guessed from its folder.

## Why these belong together

| Trap | What succeeded | What was actually read |
| --- | --- | --- |
| stale copy | your edit applied to a real file | a different file |
| BOM | DML parsed the line | comment text as a mod name |
| missing `info.json` | DMF queried metadata | an empty table |

None of the three throws. Each one produces a confident-looking result that is about a
different object than the one you were thinking about. That is the same failure as a patch
applied to a source table while the runtime reads a copy — which is why this file sits beside
`copy-semantics.md` rather than in a separate skill about installation.

## Provenance

Trap 1 and Trap 2 are **first-hand incidents from this project**, each with a log line or a byte
check. The "most mods have no `info.json`" observation and the fallback chain were **read from the
framework source and a real mod directory**, not inferred. Trap 3's *consequences* are reasoning
from that code; the code itself was read directly.
