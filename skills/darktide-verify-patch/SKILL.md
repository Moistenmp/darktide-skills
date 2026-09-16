---
name: darktide-verify-patch
description: "Diagnose and prevent Warhammer 40,000: Darktide data patches that apply successfully but have no observable effect. Use for CDP / data-pack patches, DMF mod tweaks, or any value change that reports success while the game behaves unchanged, and for verifying that a change actually landed before claiming it works."
license: MIT
metadata:
  author: Moistenmp
  version: "1.0.0"
  repository: https://github.com/deluxghost/darktide-skills
---

# Verify That A Patch Actually Took Effect

## The symptom this skill exists for

A patch reports success — it is registered, selected, applied, logged `applied`, no error, no
fail-closed rollback — and **the game behaves exactly as before.**

Nothing is broken. Nothing warns you. Two independent mechanisms produce this, and both are
common enough that you should assume one of them is in play until you have ruled them out.

```text
Patch applied, no effect observed
├── A. The patch wrote to a table nothing reads at runtime   → see "Cause A"
├── B. The patch was never applied in this session           → see "Cause B"
└── C. You edited a file the mod does not load               → see "Cause C"
```

**Check B first.** It is cheaper, and if B is true then A is not even in question.

## Cause C — the thing you edited is not the thing that runs

The rule in Cause A — *patch the copy the runtime reads, not the source it was copied from* —
applies to **files** as well as tables. A stale sibling `.lua`, a byte-order mark that makes a
comment parse as content, and metadata that fails silently all produce the same result: your
edit landed on a real file, and something else was read.

Three traps, their signatures, and how to confirm each:
[`references/file-level-traps.md`](references/file-level-traps.md).

## Cause B — the patch was never applied

Data packs are **not** applied continuously. They are applied at specific session states and
**rolled back** when the session leaves them. A log line reading
`registered ... enabled=true` establishes **registration only** — never that the values are live.

Verify, in the log, in this order:

1. The pack is registered and selected for **this machine** (console commands such as
   `/cdp_select` or `/cdp_ui` set per-machine selection).
2. The session entered an applicable state, e.g. `SessionState idle -> host_training_range`
   or `idle -> host_preparing`.
3. The runner actually applied it, e.g. `PatchRunner applying package '<id>' with N patch(es)`.

If the session is an ordinary match rather than a host/training-range state, **patches are not
applied at all** and there is nothing to debug in your patch content.

Leaving the state rolls patches back in reverse order (script → hook → value). Persistent
tables and game-side mutations may survive this; do not infer "rolled back" from the log line
alone if your patch mutated state rather than a table field.

Full treatment — what is confirmed versus inferred, and what it means for testing:
[`references/session-lifecycle.md`](references/session-lifecycle.md).

## Cause A — the patch wrote to the wrong table

This is the one that wastes days, because the patch is genuinely correct *as a patch*.

### The rule

> **If the source contains a module-level table construction of the form `X = Y.some_field`,
> and the runtime reads `X`, then patching `Y` has no effect — it only changes where the copy
> came from. You must patch `X`.**

The corollary is the part that changes how you work:

> **Before declaring a patch correct, locate the value's actual runtime read point in the source.
> Do not target the table whose name merely looks right.**

In every worked case below, the read point was **not** the table that looked like the source of
truth. See `references/copy-semantics.md` for three fully worked examples with exact anchors.

### How to find the real read point

1. **Build the source index first** (see `darktide-source-search`, upstream — listed under
   Related). You cannot grep a source tree you have not extracted.
2. **Grep for the field name, and enumerate every hit.** A field with only 2–3 hits total is
   tractable — read all of them and classify each as *definition*, *copy*, or *read*.
3. **Classify by position, not by name.** A hit inside a module-level table literal is a copy.
   A hit inside a function body, reached from an extension's update/query path, is a read.
4. **Confirm object identity before assuming a copy is stale.** A field assignment into another
   table is not always a value copy — if the receiving table stores a *reference* to the source
   table object, mutating either is equivalent. Walk the assignment sites and check whether the
   value is captured by value or by reference.
5. **Only then write the patch**, against the read point.

### The two shapes of `format_values`

UI-displayed numbers are a frequent special case, because a display value may be either a live
lookup or a value captured once at module load. The distinction decides whether changing the
truth value updates the tooltip:

| Shape | Evaluated | Does the UI follow a change to the truth value? |
|---|---|---|
| The field holds a **reference to the source table** | at read time | yes |
| The field holds a **static value copied at module load** | once, at load | **no** — patch the display field directly |

Inspect the node's `format_values` entries before assuming a functional patch covers the tooltip.
Some entries resolve dynamically through a `find_value`-style function; those do follow. Others
are plain literals; those do not.

### The structural cause, stated generally

Module construction happens during startup. Patch application happens later. Therefore **any
value captured by copy during module construction is already a literal by the time your patch
runs**, and your patch cannot reach it.

> ⚠️ **Provenance of the ordering claim.** That patch application is later than module
> construction is **inferred** from three observed phenomena (patch reports applied + runtime
> value unchanged + a load-time copy exists at that site), not read as an explicit ordering
> assertion in the loader's own source. Treat it as a working model. The *rule* above does not
> depend on it — the rule is just "patch the read point".

## Declaring success: the four-segment chain

A change counts as landed only when all four segments are visible. Segment 4 is where most
false claims originate.

| # | Segment | What it looks like |
|---|---|---|
| 1 | **Declared** | the pack is registered with its version |
| 2 | **Registered** | the pack's data is parsed, `N patch(es)` |
| 3 | **Applied** | the runner applies it; per-patch `applied` lines |
| 4 | **Business output** | **the mod's own runtime behaviour changed** |

> **Segment 4 must be the mod's own business output — not loader echo.**
> `PatchRunner applied value: ...` is the **loader reporting about itself**. It is segment 3.
> It is strong evidence the patch is well-formed (a fail-closed loader rolls the whole batch
> back and prints nothing on a bad path), but it is **not** evidence the game changed.

Numerical-only patches frequently have **no** natural segment-4 log line. In that case you do
not get to claim all four. Either build an in-game readback, or state plainly that segments 1–3
are confirmed and 4 is not.

### Building segment 4: read the live table in-game

The strongest segment-4 evidence is a command that reads the **actual runtime table** and
compares it against the declared intent, rather than printing what your patch file says.
Implement it as a console command in the pack itself and have it report per-entry agreement.

Two properties worth copying from an implementation that works:

- **Print the value the game is actually holding**, fetched through the same call path the
  consuming code uses — not through your own re-derivation of it.
- **Make it say "no such section" rather than fabricate.** If a section is meaningless for that
  pack, the command must print that explicitly. A command that silently prints nothing is
  indistinguishable from one that found nothing.

## Hard rules

- **Never claim a patch works on the strength of `applied` alone.** That is segment 3.
- **Never patch a table because its name matches the concept.** Find the read point.
- **A patch that is structurally valid can still be semantically dead.** Loader acceptance is
  not effect.
- **"The conflict detector reported no conflict" ≠ "there is no conflict."** Patches that write
  game tables directly at runtime, outside the patch framework, bypass conflict detection, batch
  rollback, and error reporting entirely — last loaded wins, silently. Audit those separately.
- **Re-verify anchors when the game updates.** A decompiled line number is valid for one game
  build only; re-check the anchor still lands on the construct you think it does.

## Related

**The four skills below are not part of this repository.** They are upstream work by a different
author, published at <https://github.com/deluxghost/darktide-skills>. They are listed because
they are genuinely complementary, but you will not find them here — fetch them from that
repository separately.

- `darktide-modding` (upstream) — DMF hook, settings, lifecycle, and reload mechanics
- `darktide-dt-cli` (upstream) — live log streaming and **live Lua state queries** in a running
  game. This is the natural way to read a live table for segment 4 instead of inferring it.
- `darktide-diagnosis` (upstream) — reading logs and tracing a cause **from a symptom**. That
  skill is broader than "when something throws": it also covers intervals where no exception
  explains the symptom, using state/connection/subsystem messages instead.
  **The difference from this skill is the direction of the question.**
  Diagnosis starts from *an observed symptom* and looks for its cause.
  This skill starts from *a change you made* and asks whether it reached the value the game
  reads at runtime — a case where there may be no symptom at all, because the change was
  accepted silently and simply had no effect.
- `darktide-source-search` (upstream) — obtaining and querying the decompiled source tree

## Format note

Upstream skills carry a richer frontmatter (`license`, `metadata.author`, `metadata.version`,
`metadata.repository`) than this draft does. Those are **deliberate omissions, not oversights**:
the license and the publishing identity are the project owner's decisions and have not been
made. See [`../README.md`](../README.md).
