# In-place mutation of the options table

> Companion to `../SKILL.md`. **Verified by reading the DMF source**, anchors below.
> Valid for one DMF build; re-check the line numbers before relying on them.
>
> **Third-party code notice.** The excerpts below are from Darktide Mod Framework, which is
> distributed under the MIT License, Copyright (c) 2018 Vermintide Mod Framework. They are
> quoted here to document the behaviour described, and the framework's license permits this.
> The full license text is in `THIRD-PARTY-NOTICES.md` at the root of this repository.
> Darktide Mod Framework is not affiliated with this repository.

## The code, in full

`<game>/mods/dmf/scripts/mods/dmf/modules/core/options.lua`

```lua
:307  local function initialize_dropdown_data(mod, data, localize, collapsed_widgets)
:308    local new_data = initialize_generic_widget_data(mod, data, localize)
...
:311    new_data.options      = data.options            -- ← a reference
...
:313    validate_dropdown_data(new_data)
:314    localize_dropdown_data(mod, new_data)
:315
:316    -- Converting show_widgets from human-readable form to dmf-options-readable
:317    -- i.e. {[1] = 2, [2] = 3, [3] = 5} -> {[113] = true, [114] = true, [116] = true}
:318    -- Where the 2nd set of numbers are the real widget numbers of subwidgets
:319    if data.sub_widgets ~= nil then
:320      for i, option in ipairs(data.options) do          -- ← iterates `data`, not `new_data`
:321        if option.show_widgets ~= nil then
:322          new_data.controls_sub_widgets = true
:323
:324          local new_show_widgets = {}
:325          for j, sub_widget_index in ipairs(option.show_widgets) do
:326            if data.sub_widgets[sub_widget_index] then
:327              new_show_widgets[data.sub_widgets[sub_widget_index].index] = true
:328            else
:329              dmf.throw_error("[widget \"%s\" (dropdown)]: 'options -> [%d] -> show_widgets -> [%d] \"%s\"' points " ..
:330                               "to non-existing sub_widget", data.setting_id, i, j, sub_widget_index)
:331            end
:332          end
:333          option.show_widgets = new_show_widgets          -- ← writes into the table from `data.options`
:334        end
:335      end
:336    end
:337
:338    return new_data
:339  end
```

## What this establishes

**`:311` is the decisive line.** `new_data.options` is assigned `data.options` — the same table
object. There is no `deep_copy`, no `table.clone`, no per-element copy anywhere in the
function. So `data.options[i]` **is** the caller's option table.

**`:320` iterates `data.options` while `:333` writes into `option`** — an element of that same
table. The write therefore lands in the table the mod passed in, after the function returns.

**The function is not idempotent.** It converts positions → widget ids. Feeding it its own
output sends widget ids into a lookup keyed by positions.

## The three consequences, with the mechanism

### 1. Registering the same options table twice

Second call, `option.show_widgets` is now `{[113] = true, [114] = true}`.

- `ipairs` over a table keyed by numbers does not iterate it as a list — the entries are
  non-sequential (`113`, `114`, `116`), so `ipairs` yields nothing and the loop body never runs.
- **Either way the result is wrong, and the loud path is the confusing one.** Where the ids
  happen to be small enough to sit in a sequence, the loop does run, `data.sub_widgets[113]` is
  `nil`, and `:329` throws a message naming index `113` — **a number that never appeared in the
  source you wrote**, because in the human-readable form the valid indices were `1..n`.

⇒ This is why the error "points to non-existing sub_widget" is worth recognising on sight: on a
first registration it means a genuine index bug; on a re-registration it is the signature of
the mutation.

### 2. Reading the field after registration

Any debug print, any conditional that inspects `show_widgets`, any code deriving one dropdown's
gating from another's, sees `{[113] = true}` — widget ids with no positional meaning. Output
captured after load cannot be diffed against the authored literal.

### 3. Deriving a second dropdown by copying

A shallow copy (`{ ... }` in Lua copies only the top level) copies the **reference** to the same
nested option tables. The copy is not a template; it is a second name for already-converted
data. A deep copy fixes the aliasing but still carries whatever values were present at copy
time — **so the copy must be taken from a source that has not passed through DMF**, which in
practice means keeping your own pristine table rather than reusing the registered one.

## Practical rule

> Build each dropdown's `options` fresh from your own untouched source table.
> **Never reuse a table that has already been handed to DMF.**
> When debugging, print the table **before** registration, not after.

## Provenance

Consequences 1–3 are **inferences** drawn from the code at `:311`, `:320`, `:326-333`, and
`:329`. The code is quoted in full above so the inference can be checked rather than taken on
trust. The in-place write and the reference assignment are **read directly, not inferred**.
