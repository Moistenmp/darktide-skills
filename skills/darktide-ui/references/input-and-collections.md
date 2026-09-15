# Input And Collections

## Input Is Part Of The Frame Pipeline

An input service exposes actions such as confirm, back, pointer presses, and held input. A `hotspot` pass translates those actions and its geometry into widget interaction state. Owner update code, hotspot passes, template logic passes, and callbacks are different stages, not independent descriptions of one instantaneous state.

`UIWidget.draw` also updates passes and runs hotspot/logic behavior. Transient fields such as `on_pressed` and `on_released` are produced and reset by that processing. Owner update code running before drawing can observe the preceding draw's state; skipping a widget's draw also skips that processing. When connecting behavior, use the control's intended callback or state-consumption point, with its actual frame order.

A `pressed_callback`, a template's logic pass, an input-legend callback, and a view's manual confirm handler can each perform an action. Decide which route owns activation. Press, hold, release, hover, selection, and focus have distinct meanings; a generic pressed flag is not a substitute for the control's complete interaction contract.

Source: `scripts/managers/ui/ui_passes.lua`, `scripts/managers/ui/ui_widget.lua`.

## Navigation, Focus, And Editing

Mouse hover follows geometry; controller navigation follows selected/focused entries. The native templates use these states differently, and `_on_navigation_input_changed` lets the owner adapt when the active device changes. Input legends likewise update their hints. Preserve the selected value separately from the indication of current keyboard/controller focus.

Input exclusivity is established at the relevant boundary. The view handler can give lower views a null input service, but a modal widget group inside one view shares that view's input unless the parent routes it. While a popup or editor is active, its parent must assign navigation, confirm/back, and pointer interaction to the intended component. A higher z or a dark backdrop does not establish that routing.

Native text-entry templates manage `input_text`, `is_writing`, caret position, selection, and UTF-8 editing. Slider templates manage their own track hotspots, drag state, and normalized `slider_value`. Treat those templates as stateful controls: let their logic perform editing or dragging, and connect application behavior at the appropriate change/commit point. Live preview, release-to-commit, and leaving an editor are different interaction choices, not one universal callback contract.

Source: `scripts/managers/ui/ui_view_handler.lua`, `scripts/ui/pass_templates/text_input_pass_templates.lua`, `scripts/ui/pass_templates/slider_pass_templates.lua`.

## Collections Have Several Layers

`UIWidgetGrid` is a layout, scrolling, and navigation controller for supplied widgets and alignment entries. It arranges instances around a scenegraph pivot and tracks visible ranges; it is not itself a renderer or a widget-resource owner.

`ViewElementGrid` is a higher-level component. It combines a grid controller with widget construction, blueprints, masking/renderers, input, and cleanup. Prefer this level when the desired collection matches its contract; use `UIWidgetGrid` when the parent already owns the surrounding rendering and interaction structure.

`ViewElementGrid` takes three kinds of information:

- **Menu settings:** `grid_size` describes the layout area, `mask_size` the clipping area, `grid_spacing` the x/y gaps, and `scrollbar_width` the scrollbar. Padding, title, and divider settings affect the usable region. The shared settings file is not a complete standalone grid configuration; callers supply the geometry.
- **Content blueprints:** keyed by widget type. `size` or `size_function` defines an entry's footprint; `pass_template` or `pass_template_function` defines its passes; `style` or `style_function` supplies overrides. `init`, `update`, and `destroy` connect entry data and resources to that presentation.
- **Layout:** an ordered list of entries whose `widget_type` selects a blueprint. The entry becomes `widget.content.entry`; the blueprint's initialization fills the actual text, icon, interaction callbacks, and other fields. A size-only blueprint can supply a spacer without creating a drawable widget.

Thus layout entries, alignment entries, and drawable widgets are related but not necessarily one-to-one lists. `entry_id` is generated for the grid's presentation; a collection index or generated entry ID is not a permanent domain identity across reconstruction.

## Grid Measurement And Navigation

A grid is not restricted to equal cells or a fixed column count. It packs entries across the available cross-axis, then starts another row or column when they no longer fit. Growth direction and the measured sizes determine whether the result is a vertical list, a horizontal strip, or a tiled collection. Headers and spacers can participate in the same layout.

Measurement uses the alignment entry's `size`, then the widget's `size` / `content.size`, with scenegraph size as a fallback. Pass `style.size` changes the drawn part, not that measured footprint. The controller writes widget offsets and content row/column information; changing an entry's measured size requires realignment and scroll-size updates, not only redrawing its text.

Navigation uses the arranged geometry and interactable widgets' `content.hotspot`. Selecting a grid index, focusing an index, scrolling to it, and displaying a selected value are separate operations. Settings such as `use_is_focused_for_navigation` and `use_select_on_focused` decide how navigation connects focus and selection. The grid already owns neighbour selection and scrolling; a parent supplies higher-level routing between components.

The blueprint receives the grid element as its owner. Its callbacks are not interchangeable with a view method or a pass callback: the element supplies the widget, entry/configuration, renderer, and callback names at the appropriate phase.

`present_grid_layout` can defer presentation, so use its completion path when subsequent work needs the new widgets. Blueprint update callbacks can be limited to visible entries or visibility changes. Keep data updates that must happen for every entry outside visibility-dependent presentation callbacks.

## Scrolling And Drawing

The standard collection uses several distinct regions:

- `grid_background`: the area against which entries are laid out.
- `grid_content_pivot`: the moving scenegraph origin shared by entry widgets.
- `grid_mask`: the visible clipping region.
- `grid_interaction`: the region used for pointer interaction with the grid.
- `grid_scrollbar`: a separate widget representing progress and accepting scroll input; `assign_scrollbar` connects it to the pivot and interaction area.

A scrolling collection coordinates content size, widget offsets, pivot position, scrollbar progress, navigation focus, and the visible range. The grid's internal progress drives culling, while the pivot determines drawn placement. Scrollbar assignment alone need not immediately update the pivot: grid update performs that synchronization.

When replacing or resizing content, layout/scroll synchronization precedes visibility-based drawing. The mask, interaction area, and grid's visible region describe the same viewport, but need not have numerically identical dimensions: padding and visual margins can deliberately distinguish them. Hiding a visual pass is not removing its entry from the layout.

`ViewElementGrid` separates its frame/background widgets from `_grid_widgets`, the entry widgets drawn by its collection path. It can use a resource renderer and offscreen composition for the entries, while surrounding UI uses another renderer. Clipping, icon loading, material caches, and hotspot bounds belong to that path; drawing all entry widgets directly through the parent's ordinary loop does not reproduce it. Renderer options such as `no_resource_rendering` and `use_parent_ui_renderer` change this arrangement as a unit, not just its last draw call.

## Source Entry Points

- `scripts/ui/view_elements/view_element_grid/view_element_grid_definitions.lua`: the named regions and surrounding widgets; starts with `create_definitions(settings)`.
- `scripts/ui/view_elements/view_element_grid/view_element_grid.lua`: `_create_entry_widget_from_config` shows the blueprint contract; `_on_present_grid_layout_changed` assembles the collection; `_draw_grid` shows renderer and input-boundary ownership.
- `scripts/ui/widget_logic/ui_widget_grid.lua`: `_align_grid_widgets` explains packing and measured size; `_update_scroll_progress` connects progress and pivot; selection methods connect layout geometry to navigation.
- `scripts/ui/view_content_blueprints/`: shared item blueprints. Views can supply their own blueprint tables using the same collection contract.
