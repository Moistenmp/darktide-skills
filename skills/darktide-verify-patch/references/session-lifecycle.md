# Patch session lifecycle — when a data patch is actually live

> Companion to `../SKILL.md`, Cause B. A patch can be perfectly correct and still not be applied,
> because data packs are applied at **specific session states** and rolled back when the session
> leaves them. This file records what is confirmed, what is inferred, and how to tell them apart.

## Confirmed

- **Registration is not application.** A log line stating the package is registered with
  `enabled=true` establishes only that the loader knows about it. It says nothing about whether
  any value is currently live.
- **Application is tied to session state.** Packs are applied on entry to a host/training-range
  style state (for example a transition such as `SessionState idle -> host_training_range` or
  `idle -> host_preparing`), not on game start.
- **Leaving the state rolls the patches back**, in reverse order: script → hook → value.
- **An ordinary match is not an applicable state.** In a plain (non-host) session there is
  nothing to debug — the patches simply are not applied.

## How to verify

Read the log, in order. Stop at the first thing that is missing; that is your answer.

```text
1. registered + selected for THIS machine
       └─ console selection commands (e.g. /cdp_select, /cdp_ui) set a per-machine selection.
          A pack can be installed, present, and not selected.

2. session entered an applicable state
       └─ look for the SessionState transition, e.g. idle -> host_training_range

3. the runner applied it
       └─ e.g. PatchRunner applying package '<id>' with N patch(es)

4. the mod's own business output changed        ← this is segment 4, see SKILL.md
```

Steps 1–3 are **loader echo**. They are worth having — a fail-closed loader rolls the whole
batch back and prints nothing when a path is bad, so step 3 passing is real evidence the patch
is well-formed — but **none of them shows that a game value changed.**

## Consequences for how you test

- **You cannot verify a data pack by starting the game and reading the log.** You must *enter*
  an applicable state: a training range, or hosting the relevant session type.
- **Persistent tables and direct game-state mutations may not roll back** the way table-field
  patches do. If your patch mutates state rather than assigning a field, do not assume the
  reverse-order rollback fully undoes it.
- **A patch verified once is verified for one session shape.** Re-check when the session type
  changes.

## Inference boundaries — stated explicitly

- The **ordering claim** that patch application happens later than module construction is
  **inferred** from three agreeing phenomena (patch reports applied + runtime value unchanged +
  a load-time copy exists at the target site). It is not an explicit ordering assertion read
  from the loader's own source. It is a working model; the practical rule ("patch the runtime
  read point") does not depend on it.
- **Rollback completeness** for non-field patches is **not established**. The reverse-order
  rollback is documented for the patch kinds the framework manages; behaviour of a patch that
  reached out and mutated a live table is a different question and should be measured, not
  assumed.

## Why this matters for conflict detection

Patches that write game tables **directly at runtime**, outside the patch framework, bypass
conflict detection, batch rollback, and error reporting entirely. Among such mods, **load order
decides the winner, silently** — no warning, no log, no rollback.

> **"The conflict detector reported no conflict" is not the same statement as "there is no
> conflict."** It means "no conflict was found among the things the detector can see."

Audit runtime-mutating mods separately, and treat their interaction as a load-order question
rather than a patch-conflict question.
