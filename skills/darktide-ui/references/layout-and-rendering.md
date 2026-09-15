# Layout And Rendering

## Coordinate Spaces

A scenegraph node defines a rectangle relative to its parent: size, alignment, and local position. In the Lua layout space, x increases rightward and y downward. Center/right/bottom alignment accounts for the child's size; a centered node's local position is an offset from its aligned position, not an absolute screen coordinate.

`UIWorkspaceSettings` supplies screen and panel layouts. The familiar 1920 × 1080 canvas is a reference layout, not a claim about the actual display resolution. Root scale policies such as `fit`, `fit_width`, and `fit_height`, together with the renderer's scale, map UI units to the current screen. HUD scaling is an additional choice made by the HUD owner.

Use scenegraph relationships for placement within a layout, widget offsets for placing instances such as grid entries, and pass style offsets/sizes for details within a widget. A pass can select another scenegraph node. Keep these coordinate spaces distinct when comparing cursor positions, measured text, and drawn geometry; native input code converts with the relevant renderer's inverse scale.

Normally a pass starts with the widget's `content.size`, falling back to its scenegraph rectangle. Pass style `size` overrides dimensions, `size_addition` expands or contracts them, and style alignment/offset places that result inside the widget. These are visual dimensions, not an automatic update to the widget's layout footprint. The scenegraph is explicit rectangle layout, not content-driven reflow: text length or a larger decorative pass does not automatically resize a panel or move its neighbours.

Runtime scenegraph geometry is resolved data. Change it through the owner's layout helpers, or update the scenegraph after changing local positions/sizes. Editing the original definition alone does not move an existing node. Full-screen backgrounds and fixed-width content panels can require different root scale policies on wide displays.

Source: `scripts/managers/ui/ui_scenegraph.lua`, `scripts/settings/ui/ui_workspace_settings.lua`.

## Widgets And Pass Data

A live widget has a scenegraph attachment, an ordered pass list, `content`, `style`, and an offset. Each pass selects its data through three independent identifiers:

- `content_id`: selects `widget.content[content_id]`; without it, the pass uses the root `widget.content`.
- `value_id`: selects the value within that chosen content table, such as text or a material name.
- `style_id`: selects `widget.style[style_id]`, containing that pass's geometry, color, font, or material settings.

The factory can generate IDs when they are omitted. A text pass does not imply a field called `text`, nor does every control use `content.hotspot`. Explicitly shared IDs can make passes share state or styling. Resolve fields from the constructed definition rather than guessing them from the pass type.

Pass callbacks receive the selected pass content/style, which may be nested rather than the widget's root tables; drawing supplies `.parent` links to those root tables. `visibility_function` gates a pass; `change_function` can alter its presentation during drawing. A `logic` pass runs behavior without producing a visible primitive. Passes run in list order, so one pass can consume state produced by an earlier pass.

The standard `BaseView`, `ViewElementBase`, and `HudElementBase` `_create_widget` helpers add the widget to the name map, but not to the ordinary `_widgets` drawing array. Dynamic widgets need an actual drawing path, either that array or a component's custom draw loop. Widget creation, lookup, and drawing are separate operations.

Source: `scripts/managers/ui/ui_widget.lua`, `scripts/managers/ui/ui_passes.lua`, `scripts/ui/default_pass_styles.lua`.

## Pass Types And Their Uses

The game widget dispatcher in `scripts/managers/ui/ui_passes.lua` defines the following 19 pass types. The table covers that Lua layer, not every lower-level `Gui` function. Here, **value** means the field selected by `value_id` in the pass's content; the named geometry/rendering fields are style fields unless noted otherwise.

| Pass type | Purpose | Main data and distinctions |
| --- | --- | --- |
| `rect` | Solid panels, backdrops, simple bars | `color`; the resolved pass rectangle supplies size. |
| `rotated_rect` | Rotated solid rectangle | `color`, `angle`, `pivot`; pivot is local to the rectangle. |
| `triangle` | Filled triangle, pointers, wedges | `color`; `triangle_corners` supplies three local 2D points, or `triangle_alignment` chooses a rectangle-corner triangle. |
| `circle` | Filled circular area | Size and `color`, with `circle_horizontal_alignment` / `circle_vertical_alignment` controlling centre placement. Drawn as a triangle fan. |
| `texture` | GUI-material image: icons, frames, backgrounds | Value is the material; `color` tints it. `material_values` supplies shader parameters or texture slots. |
| `texture_uv` | A selected region of a material's image | As above, plus `uvs = {{u0, v0}, {u1, v1}}`; UVs select image coordinates independently of rectangle size. |
| `rotated_texture` | Rotated material image | Value, `angle`, `pivot`, `uvs`, and `color`. |
| `multi_texture` | Repeated images or a sequence of images | Value is one material or an array; `amount`, `axis`, `direction`, and `spacing` arrange the copies. Size is per copy. |
| `shader_tiled_texture` | Material-driven repeating pattern | Material must support `tile_multiplier` and `tile_offset`; `tile_size` and `tile_offset` control repetition. This specialized pass has no matching standard factory defaults. |
| `text` | Display text | Value is resolved text; `font_type`, `font_size`, `text_color`, and text alignment control drawing. It does not localize a key or implement text editing. |
| `slug_icon` | One indexed shape from a vector resource | Value is a vector resource, `draw_index` selects the shape; `color` and optional `material` control rendering. |
| `slug_picture` | A complete vector picture | Value is the vector resource; the picture is drawn as a whole rather than selecting one `draw_index`. |
| `rotated_slug_icon` | Rotated indexed vector shape | The icon fields plus `angle` and `pivot`. |
| `multi_slug_icon` | Repeated indexed vector shape | The icon fields plus `amount`, `axis`, `direction`, and `spacing`. |
| `hotspot` | Interactive hit region | Writes hover, press, hold, release, focus/selection animation state and invokes callbacks. It draws no visible control. |
| `hover` | Hover-only region | Updates content `is_hover` / `internal_is_hover`; does not provide the hotspot activation contract. |
| `logic` | Geometry-aware per-draw control logic | Value is a function called as `(pass, ui_renderer, ui_style, ui_content, position, size)`. |
| `video` | Display an existing video player | Value is the video material; content `video_player_reference` selects the managed player and `video_completed` reports completion. Player creation/loading is separate. |
| `debug_cursor` | Diagnostic interaction rectangle | Colors the region from interaction state; not a production control template. |

`slug_*` uses the game's vector resources, not raster texture UVs or arbitrary SVG filenames. Rotation uses radians; repeated passes use `axis = 1` for x and `axis = 2` for y, with `direction` setting the sign. These variants do not enlarge the widget's measured footprint or hotspot automatically. A hotspot normally tests a rectangle; content `hover_type` can select circle or triangle testing, with `triangle_corners` supplying the latter's geometry.

Pass types are selected by actual entries in `UIPasses`, not by default tables or renderer method names. Factory support is a separate boundary: `UIWidget.create_definition` only copies pass-template `style` and `value` through branches with matching `DefaultPassStyles` and `DefaultPassValues` entries, respectively. For `shader_tiled_texture`, these entries are absent; supplying the ordinary template fields alone does not construct the required data. Assemble its definition's pass IDs, content, and style explicitly. Retained rendering and material customization are pass-specific capabilities, not guarantees shared by every row.

## Native Appearance And Text

`scripts/ui/pass_templates/` contains compositions for buttons, sliders, text entry, items, and other surfaces; these often include animation and interaction logic alongside visuals. Reuse the appropriate template or factory as a whole, then customize the intended fields. Pair it with a caller from the same control family to understand its state and callback contract.

`UIFontSettings` provides font/style presets; `Color` provides the game's palette. Lua UI colors normally use `{ alpha, red, green, blue }` in the 0–255 range. Changing opacity and replacing RGB are different operations. Native style functions or animations may recompute these values each frame, so a one-time assignment may not own the final appearance.

Text alignment places glyphs inside a pass rectangle; scenegraph alignment places the rectangle itself. Measure resolved display text with `UIRenderer.text_size` and the matching font options from `UIFonts`, using the same scale and units as the layout. Character counts do not determine display width. Wrapping, truncation, available width, and localized text length are layout decisions; preserve the template's UTF-8-aware editing behavior for text fields.

Input legends provide action-aware keyboard/controller hints and can execute callbacks; they are not just decorative labels. Use native hover, focus, disabled, and editing states so appearance communicates the control's actual behavior.

Source: `scripts/managers/ui/ui_font_settings.lua`, `scripts/managers/ui/ui_fonts.lua`, `scripts/ui/view_elements/view_element_input_legend/view_element_input_legend.lua`.

## Composition, Materials, And Animation

`UIRenderer.begin_pass` supplies a scenegraph, input service, time, and render settings for widget drawing. Layering combines scenegraph z, widget/pass offsets, and the owner's `start_layer`. A larger local z is not a universal way to cross renderer, viewport, or view-stack boundaries.

A scenegraph rectangle does not clip its children. Scrollable content uses compatible masks, material passes, and renderer setup. Masking clips pixels, culling chooses which widgets are drawn, and hit testing chooses which interactions are accepted; these are separate mechanisms. Transparent content can still receive input, and a clipped item needs the collection's input bounds as well as its visual mask.

Texture passes commonly name engine GUI materials, not arbitrary image files. Their material can define texture slots, UVs, shader parameters, and masking behavior. In supported passes, `material_values` maps parameter names to numbers, numeric arrays, texture-resource names, or resource handles. The containing resource packages must be loaded for the lifetime of the renderer's references. Reusing a material name does not load its package.

A material path is a resource name; the resulting GUI material and retained drawing IDs belong to the GUI context that created them. Passes can cache those objects in `pass.data`. Sharing a definition is different from moving an already initialized, resource-caching widget to another GUI context. The boundary is the underlying GUI, including retained versus non-retained GUI, rather than the Lua renderer variable's name. This matters especially when a collection has its own resource renderer while its parent draws other widgets.

`UISequenceAnimator` runs named, timed sequences over widgets and scenegraphs; widget animations and pass `change_function` callbacks can also produce transitions. Determine which of these drives a value before adding another writer. Preserve completion callbacks when they advance the view's opening or closing lifecycle.

Retained-mode passes cache engine drawing resources. Changing their Lua data requires the appropriate widget/pass dirty flag, and removal requires resource destruction, not merely removing a Lua table from a list. Use the owner's retained-mode lifecycle when extending retained HUD content.

Source: `scripts/managers/ui/ui_renderer.lua`, `scripts/managers/ui/ui_sequence_animator.lua`, `scripts/managers/ui/ui_animation.lua`.
