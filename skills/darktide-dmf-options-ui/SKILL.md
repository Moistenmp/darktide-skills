---
name: darktide-dmf-options-ui
description: "Build and debug the DMF mod-options UI: widget types, the settings tree, dropdown gateways that show and hide other widgets, tabs, and colour pickers. Use when a DMF option does not appear, appears in the wrong place, is not a tab, shows nothing, or when writing an options table, options.lua or a color/numeric/dropdown/keybind widget."
license: MIT
metadata:
  author: Moistenmp
  version: "1.0.0"
  repository: https://github.com/deluxghost/darktide-skills
---

# DMF Options UI

Darktide Mod Framework renders every mod's settings page from one declarative table your mod
registers in its data file. This skill covers that table: how DMF reads it, how the settings
tree is assembled, and — the part that costs the most time — **what DMF does *not* tell you
when it goes wrong.**

All paths below are relative to `<game>/mods/dmf/scripts/mods/dmf/`.
Line anchors are valid for one DMF build only; re-verify before relying on one.

## The governing fact: two layers, two failure styles

`modules/core/options.lua` is roughly 800 lines and is almost entirely `dmf.throw_error` calls.
DMF validates the **structure** of your options table at load time, loudly, naming the widget.

That is not where your time will go. Split the problem:

| Layer | DMF behaviour | Your experience |
| --- | --- | --- |
| **Structure** — types, required fields, duplicate `setting_id`, duplicate option `value`, bad `show_widgets` index, a `group` with no sub-widget, `range[2] <= range[1]`, … | **throws**, with a message naming the widget and field | Read the message. Done. |
| **Behaviour** — is this group a tab, is this row visible, does this dropdown reveal those widgets, is that widget hidden right now | **no error, ever.** Silent by design. | **This is the hard part.** |

So: **a clean log does not mean your options UI is correct.** It means your table was
well-formed. Every question about what the user actually sees is in the second row.

## The mutation rule — read this before reusing an options table

**DMF rewrites your options table in place.**

`modules/core/options.lua`, dropdown initialization:

```lua
:311   new_data.options      = data.options        -- a reference, not a copy
...
:319   if data.sub_widgets ~= nil then
:320     for i, option in ipairs(data.options) do
:321       if option.show_widgets ~= nil then
:322         new_data.controls_sub_widgets = true
:324         local new_show_widgets = {}
:325         for j, sub_widget_index in ipairs(option.show_widgets) do
:326           if data.sub_widgets[sub_widget_index] then
:327             new_show_widgets[data.sub_widgets[sub_widget_index].index] = true
:328           else
:329             dmf.throw_error(... "points to non-existing sub_widget")
:333         option.show_widgets = new_show_widgets    -- writes back into YOUR table
```

The comment above `:316` states the transformation exactly:

```text
-- Converting show_widgets from human-readable form to dmf-options-readable
-- i.e. {[1] = 2, [2] = 3, [3] = 5} -> {[113] = true, [114] = true, [116] = true}
-- Where the 2nd set of numbers are the real widget numbers of subwidgets
```

You write **positions** into that dropdown's own `sub_widgets`. After registration the same
field holds **widget ids**. Consequences, all of which are silent until they are not:

1. **One options table serves exactly one dropdown.** Register it twice and the second pass
   reads converted data: `data.sub_widgets[113]` is nil, so it throws
   `...points to non-existing sub_widget` — **naming an index that looked valid in the form
   you wrote**, which sends you looking in the wrong place.
2. **Printing `show_widgets` after load shows widget ids, not positions.** Debug output taken
   after registration cannot be compared against what you wrote.
3. **A shallow copy of the options table carries converted data.** Copying an options table to
   derive a second widget group does not give you a clean template — deep copy it *and* make
   sure the source you copied from has not already been through DMF.

⇒ Keep your own pristine source table, and build each dropdown's options from it fresh.

The full function, quoted with its anchors, and the three failure mechanisms worked through
step by step: [`references/in-place-mutation.md`](references/in-place-mutation.md).

## Tabs are three conditions, not one

A group becomes a tab only when all three hold (`modules/ui/options/mod_options.lua:757-759`):

```lua
template.is_options_tab_candidate = widget_data.depth == 0
  and <has sub-widgets>
  and has_focusable_descendant(mod_data, i)          -- defined at :547
```

A top-level group whose children are all non-focusable (containers, labels, nested groups with
no focusable leaf) is **not** a tab and produces no error — it renders nowhere. When a section
"disappears", check for a focusable descendant before checking anything else.

## Dropdowns as gateways

`show_widgets` is how a dropdown reveals and hides the rest of the page. Get the mental model
right once:

- An **empty table** means "show nothing" — a legitimate way to hide everything for an option.
- Indices are **1-based positions into that dropdown's own `sub_widgets`**, not global widget
  numbers and not `setting_id`s. An index outside the range throws (`:329`).
- DMF sets `controls_sub_widgets = true` (`:322`) on the dropdown, which is what makes it a
  gateway rather than a plain selector.
- Because of the mutation rule above, the *positions* you author are the right thing to write
  and the wrong thing to read back.

## Widget reference

Validation for each type lives in `modules/core/options.lua` and reads as its own
documentation. The most useful entries:

| Type | Anchor | Rules worth knowing |
| --- | --- | --- |
| generic | `:68`, `:73`, `:77`, `:81`, `:86` | `setting_id` required; `title` required when localization is off; `tooltip` must be a string; **duplicate `setting_id` across widgets throws** |
| group | `:148` | must have at least 1 sub-widget |
| dropdown | `:240`–`:287` | `default_value` must be one of `options[].value`; ≥2 options; **two options with the same `value` throws** (`:275`) |
| keybind | `:382`–`:396` | ≤4 keys, no duplicate key in `default_value` |
| numeric | `:522`–`:559` | `range` must be 2 numbers, `range[2] > range[1]`, `default_value` inside range |
| color | `:592` | `has_alpha` must be boolean |
| text | `:424`–`:454` | `max_length`, optional `validate`; `stored setting must have 'string' type` (`:488`) |

**The colour widget** takes `default_value`, `display_name`, `has_alpha`, `setting_id`,
`tooltip_text`, `require_restart`, `indentation_level` and stores **`{ a, r, g, b }` — alpha
first**, which is the opposite of the `{ r, g, b, a }` order used elsewhere in the game.
Getting this backwards is not an error; it just changes the wrong channel.

## Localized text is always formatted

`mod:localize` runs `string.format` unconditionally. **A literal `%` in a display name or
tooltip must be written `%%`.** The failure is a formatting error naming the offending string —
loud, but the message points at the format call, not at your options table.

## A local convention, not a DMF feature

**The pattern below is not part of DMF.** It is a convention one mod used to make a settings row
show a live value instead of a static one: wrap the row in a small evaluator, and let the
evaluator return a tri-state about whether it could produce a value at all. **Do not cite it as
a framework behaviour** — nothing in DMF knows about `value_fn`.

The evaluator contract looks like this:

```lua
local ok, text, fraction = pcall(field.value_fn, ctx)
if not ok      then return nil, nil, "value_fn_error" end
if text == nil then return nil, nil, "unavailable"    end
```

Two properties are worth copying into any dynamic row: the evaluator is `pcall`-guarded, and
**returning `nil` is a first-class answer meaning "not available right now"** — the row hides
rather than showing a stale or invented number. This is our design, not DMF's; DMF has no
`value_fn`. Attribute it accordingly if you reuse it.

## When something does not show up

Work this order — it goes from most common to least, and the first three cost one look each:

1. **Read the log for `dmf.throw_error`.** If the table was malformed you already have the
   answer, with the widget named.
2. **Is the group a tab?** All three conditions at `:757-759`. A group with no focusable
   descendant is silent, not broken.
3. **Is a dropdown gateway hiding it?** A page whose widgets are gated by `show_widgets` shows
   only what the current option selects. Check the *selected* option, not the one you meant.
4. **Did you reuse an options table?** See the mutation rule. Look for a table that reaches DMF
   twice, or a copy derived from an already-registered source.
5. **Is your row's evaluator returning `nil`?** That hides it by design; the row is working.

Only after those: suspect DMF itself.

## Provenance

Everything above was read from the DMF source with the anchors shown. **One item is marked as
our convention rather than DMF's** — the `value_fn` evaluator contract, which DMF does not have.
The claim that a second registration of the same table is what produces the confusing
`show_widgets` error is an **inference** from `:311` + `:333` + `:329` — consistent and
mechanistically forced by the code shown, but not stated by DMF itself.
