# Copy semantics — three worked cases

> Companion to `../SKILL.md`, Cause A. Every anchor below was verified against the decompiled
> source tree at the time of writing. **Line numbers are valid for one game build only.**
> All three cases share one shape: a value is copied at module construction, the runtime reads
> the copy, and the table that *looks* like the source of truth is never read.
>
> **This file cites locations, not code.** Paths and line numbers are given so you can open the
> site yourself in your own copy of the source tree; the surrounding text describes what is
> there in prose. Nothing here reproduces game source.

## Case 1 — grenade charges: patching the talent setting does nothing

The value a player experiences is the charge count on the **ability table**, not the talent
setting that appears to configure it.

**The copy site** — `scripts/settings/ability/player_abilities/abilities/broker_abilities.lua`.
Each ability entry assigns its `max_charges` field from a `talent_settings.blitz.*` default at
table-construction time. Four ability entries do this. Read the file and you will see the
assignment; note that it is a **plain value assignment**, not a reference to the settings table.

**The read point** — `scripts/extension_systems/ability/player_unit_ability_extension.lua:839`.
The function `max_ability_charges` (roughly `:823-854`) reads the charge count off the ability
object it was handed. `:801-813` is the sibling `remaining_ability_charges`.

**Why the copy is stale.** The ability table is stored **by reference**, not cloned, so the
runtime is reading the same object the constructor built — but that object's `max_charges` was
already frozen to a number. The relevant hops are:

```text
:425  equipped ability resolved by name from the ability registry
:239  stored on the extension's equipped-ability table by reference, not cloned
:831  fetched back out by ability type at runtime
:839  the charge count is read off that object  <- the real read
:850  a stat buff may be applied on top of it
```

**Conclusion.** Patch `broker_abilities.broker_*.max_charges`. Patching
`talent_settings_blitz.*` changes only where the copy came from — the copy already exists.

## Case 2 — dome cooldown: three hits, only one of them is the truth

**Definition** — `scripts/settings/talent/talent_settings_psyker.lua:259` holds the dome's
`cooldown_sphere` default as a bare number.

**Copy** — `scripts/settings/ability/player_abilities/abilities/psyker_abilities.lua:65`, inside
the `psyker_force_field_dome` ability, assigns that setting into the ability's own cooldown
field.

**Read point** — `player_unit_ability_extension.lua:766`, the first line of
`max_ability_cooldown` (roughly `:758-770`), which reads the cooldown off the ability object.

A whole-source grep for `cooldown_sphere` returns **three** hits: the copy, a UI-side static
copy, and the definition. None of them is the read point.

**Trap.** The same ability table also carries plain `cooldown` and `cooldown_reduced` fields —
those belong to the **combat ability itself**, not to the dome. They are not interchangeable, and
choosing the wrong one produces a patch that applies cleanly and changes nothing you can see.

## Case 3 — tooltip value: captured once, never refreshed

`scripts/settings/talent/archetype_talents/talents/veteran_talents.lua` builds a tooltip entry
for the shout ability. The entry's `format_values` table has a `cooldown` key of
`format_type = "number"`, whose `value` field is assigned **directly from the ability table's
cooldown field** at module-construction time (the shouts block, around `:557-560`).

That `value` is evaluated **once, when the module is constructed**. Changing the ability's
cooldown therefore does **not** update the tooltip. The tooltip needs its own patch, pointed at
`...format_values.cooldown.value`.

## The generalisation

> **`X = Y.some_field` at module level, runtime reads `X` ⇒ patch `X`, not `Y`.**

Before patching, classify every grep hit for the field name as **definition**, **copy**, or
**read**, and patch the read. Do not select a target because its name matches the concept.

## Second form: static copy vs dynamic lookup in `format_values`

| Shape | Evaluated | UI follows a change to the truth value |
|---|---|---|
| field holds a reference to the source table | at read time | **yes** |
| field holds a literal copied at module load | once | **no** — patch the display field itself |
| field resolved through a `find_value`-style function | at read time | **yes** |

Inspect each `format_values` entry individually. A single node can mix all three.

## Provenance note

The claim that patch application happens **later** than module construction is **inferred** —
from three phenomena agreeing (patch reports applied, runtime value unchanged, a load-time copy
exists at the site) — not read as an explicit ordering assertion in the loader source.
The rule itself does not depend on that inference: it is simply "patch the read point."

Reading the three files above is what establishes each case. **The anchors are the evidence; the
prose is a description of them.** If a line number has drifted to a different build, re-read the
file — the shape (`X = Y.field` at module level) is what you are looking for, not the number.
