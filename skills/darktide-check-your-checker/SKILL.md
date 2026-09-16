---
name: darktide-check-your-checker
description: "Build a validator, precheck, or linter for Darktide mod code and prove it actually works. Use when writing or changing a check script, a CI gate, a precheck, or a negative test, and when a check reports success, reports a suspiciously large number of problems, or finds nothing at all."
license: MIT
metadata:
  author: Moistenmp
  version: "1.0.0"
  repository: https://github.com/deluxghost/darktide-skills
---

# Check Your Checker

Every Darktide mod project grows check scripts: deploy prechecks, patch validators, options
guards, load-order linters. They all share one property — **they report success by default.**
A checker that is wrong, blind, or misaimed produces a green result that looks exactly like a
correct one.

This skill is about the second-order problem: **how do you know your checker works?**

## The rule

> **Before trusting a green result, make your checker fail on purpose.**
> Feed it a case you know is bad. If it passes that too, you have learned nothing about the
> real input — you have only learned that the checker is quiet.

A checker is code. It gets the same treatment as code you ship: a negative test, run for real,
with the output read.

## What a negative test must actually do

A negative test is **not** "call the checker on the current tree and confirm it exits 0." That
is the positive path with extra words. It must:

1. **Start from a copy of real, currently-passing input.**
2. **Inject one specific known-bad property** — the exact defect class the check exists to
   catch.
3. **Assert the checker catches it.**
4. **Prove the injection happened.** An anchor that silently fails to match turns the whole
   test into a no-op that always passes. **Throw if the injection finds nothing to change.**

Step 4 is the one people skip, and it is the one that makes negative tests lie.

## Failure catalogue — five ways this has actually gone wrong

All five are from one project's history. They are grouped because they are the same defect at
different layers: **something was trusted without being checked, and it did not announce
itself.**

### 1. The checker counted the wrong thing

A knowledge-inventory generator scored documents by how densely they cited verifiable code
anchors. Its regex accepted `.md:123` as an anchor alongside `.lua:123`.

Result: a terminology table that cited other *documents* line-by-line scored **2.8× the
runner-up**, because document-to-document references are dense and code references are not.

**The symptom was not an error — it was an outlier.** A 2.8× gap over everything else was the
only signal. ⇒ **When one result dominates the rest, suspect the metric before believing the
result.** Fix: accept only anchors that point at code, not at other prose.

### 2. The checker matched a substring where it needed a key

A validator confirmed required YAML keys with `if key not in text`. A negative test renamed
`default_prompt` to `_removed_default_prompt` — and the check **passed**, because
`_removed_default_prompt` *contains* `default_prompt`.

⇒ **Structural checks need structural matching.** A key is `^\s*key\s*:`, not a substring
somewhere in the file. Fix: anchor to line start.

### 3. The negative test's injection was wrong — not the checker

A test meant to prove "short descriptions are rejected" replaced `description: "Diagnose` with
`description: "x`, changing only the first letter. The description stayed long, the checker
correctly passed it, and the report said "blind spot."

⇒ **When a negative test reports a miss, first ask whether the injection did what you think.**
The test is code too. Distinguishing "checker is blind" from "my mutation was a no-op" is the
whole job — and reporting the first when it is the second sends you fixing working code.

### 4. The checker only looked one direction

A validator checked that every reference cited in a document exists. It never checked the
reverse: files that exist and are cited by nothing.

Adding the reverse check **immediately found a real orphan** — a reference file that had been
written and then never linked, in a skill whose check had been reporting "all passed" the whole
time.

⇒ **A one-directional check is half a check.** "References something missing" and "is referenced
by nothing" are different failures. Enumerate both ends of every relationship you validate.

### 5. The verification step damaged what it was verifying

To demonstrate that an orphan check worked, a real file was edited and restored with
PowerShell's `Set-Content -Encoding UTF8`. In Windows PowerShell 5.1 that writes a **BOM**.
The restored file began `EF BB BF`, so its YAML frontmatter no longer started at byte 0 and
every subsequent check failed.

The defect class was already known to this project — a BOM had previously broken a mod
load-order file, where it made a comment banner parse as a mod name.

⇒ **A "change something and change it back" cycle is a mutation of real state, and it can fail
without telling you.** Negative tests belong on copies, in a temp directory, never on the
artifact under test. If you must touch real files, verify bytes afterward — BOM absent, line
endings unchanged, encoding still lossless — not just "the file opens."

## The observation itself has to be validated first

A checker is not the only thing that reports success by default — **your instrument does too.**

Before concluding *"my change had no effect"*, establish that your instrument **could** have
detected the effect if it had been there. Otherwise *"I observed nothing"* and *"my instrument
cannot observe this"* are the **same result**, and no amount of further work tells them apart.

A concrete instance: an asset-injection experiment produced no visible change in-game. The
tempting next step was to keep iterating on the injection. The question that stopped it was —
*if the injection had worked, would we have seen anything?* A genuine replacement would have
been **equally invisible** through the same observation path. Continuing would have been
building on sand.

⇒ **State the positive control before trusting a negative observation.** "Nothing happened" is
only evidence once you have shown that something, had it happened, would have been visible.

## Practical habits

- **Print the count, not just the verdict.** "0 problems" and "checked 0 files" look identical
  in a green result. Emit how many items were examined.
- **Make the empty case distinguishable from the clean case.** A checker that finds nothing
  because it looked at nothing must say so.
- **Keep the historical-bug fixtures.** The most valuable negative tests are mutations of bugs
  that actually happened. When you fix a bug, add its mutation to the suite.
- **A green suite you have never seen fail is not evidence.** If you add a check and the count
  does not change behaviour on a known-bad case, you have added a decoration.
- **Re-run the suite after changing the checker.** A validator change can silently retire an
  existing anchor, at which point that test stops testing anything.

## Provenance

All five catalogue entries are **first-hand incidents from this project**, dated, with the
artifact still present. They are described by mechanism rather than by file path so the lesson
survives a refactor. The rule and the four-step negative-test contract are a **generalisation**
drawn from them, not a standard anyone published.

The *observation itself* section is likewise first-hand, from a separate workstream (asset
injection rather than code checking). It is included here because the defect is the same one —
**something was trusted without being checked** — at one level further out: not the checker, but
the instrument that feeds it. It is described by mechanism only; the findings of that workstream
are not reproduced.
