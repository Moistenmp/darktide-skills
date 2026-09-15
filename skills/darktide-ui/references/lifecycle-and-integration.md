# Lifecycle And Integration

## Views, Components, And HUD

`Managers.ui` and its view handler manage named views. `BaseView` supplies resource loading, a scenegraph, widgets, child elements, animation, and renderer integration. Opening a view starts that managed lifecycle; constructing an arbitrary view class is not an equivalent operation.

`BaseView.init` starts loading the view's requirements. The completion path creates the scenegraph and static widgets, then calls `on_enter`. Resource- and widget-dependent setup belongs at that readiness point, not at an assumed moment immediately after requesting the view. Completion is not necessarily asynchronous: with no package dependencies, `on_enter` can run before `BaseView.init` returns. Initialize derived-class data used by `on_enter` before calling the base initializer; resource readiness does not mean the derived initializer has finished. Closing can also wait for an exit animation before destruction. Registered, loading, entered, closing, and destroyed are distinct states.

A `ViewElementBase` component has its own scenegraph, widgets, and behavior, but its parent calls its update and draw methods. Standard elements draw through the renderer supplied by the parent; specialized elements can own additional renderers. `_add_element` provides managed parent-child integration. A component's local draw layer is relative to the parent's rendering context.

`HudElementBase` belongs to the player HUD rather than the view stack. HUD configuration selects element classes, visibility groups, HUD scaling, and optional retained rendering. HUD reconstruction can create a new element instance; player or HUD references are not process-lifetime objects. Visibility-group membership is the native way to associate an element with appropriate gameplay HUD states.

Inherited lifecycle methods perform real work, including updating children, managing cursor ownership and events, and destroying resources. Preserve the responsibilities of the actual base class when overriding them; call order depends on the work being extended, not a universal rule that every superclass method must run first.

Source: `scripts/ui/views/base_view.lua`, `scripts/ui/view_elements/view_element_base.lua`, `scripts/ui/hud/elements/hud_element_base.lua`, `scripts/managers/ui/ui_hud.lua`.

## View Stack And Visibility

The view handler updates the stack from the top, handling input and drawing permissions separately. A view's `_pass_input` and `_pass_draw` determine whether lower views may receive input or draw. A lower view can remain visible without receiving input; suppressing its drawing does not necessarily stop its updates.

Background drawing, passing drawing to lower views, and game-world blur are separate choices. Opening a view does not automatically paint an opaque background. A child view element's visibility flag similarly controls its drawing, not the parent's routing of update or input. Use the boundary that owns the intended behavior: view stack, child component, widget, or pass.

Source: `scripts/managers/ui/ui_view_handler.lua`.

## Mod Registration

DMF connects custom UI to the game's normal managers:

- `mod:register_view` registers a named view and its settings. The view's path and class must be reachable by the game loader. For a loose mod file loaded through that path, `mod:add_require_path` maps the exact path to DMF's file loading; it does not turn the entire mod directory into a game resource package.
- `mod:register_hud_element` registers the HUD element configuration, including its class, filename, visibility groups, and scale choices. DMF handles the registered filename's loose-file require mapping.

Use mod-specific registered names. The parent view, not a separate view registration, manages embedded view elements. Native pass templates and game components are useful building blocks; DMF's private options-view implementation is not a general-purpose control library for other mods.

Consult the current [DMF documentation](https://dmf-docs.darkti.de/) for supported registration interfaces, including [HUD elements](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Framework/wiki/hud-elements). Under the framework's `dmf/scripts/mods/dmf/modules/`, `gui/custom_views.lua`, `gui/custom_hud_elements.lua`, and `core/require.lua` show the integration with the game loader.

## Resources Belong To Lifetimes

The view settings' `package` dependency belongs to the managed view-loading path. Use it for resources the view needs throughout its life. Assets available because another screen happens to be open are not dependencies owned by the new view. Dynamic resources need a corresponding runtime owner and readiness point.

Release drawing references before unloading their packages. The normal `BaseView` destruction path destroys child elements and its owned renderer before releasing view requirements. A child borrowing a renderer must not destroy it; one creating a separate renderer, viewport, world, or resource loader must release those owned objects. Removing widgets from Lua collections alone does not release retained drawing resources.

Item or character previews can be world-backed UI: camera, viewport, spawned units, lighting, and packages sit behind the displayed region. Use the relevant preview element or spawner contract rather than treating a 3D preview as another static texture. `UIWorldSpawner` and the item/character-specific spawners manage different parts of this structure.

Mod reload does not recreate the current game state. UI instances, event subscriptions, and engine resources need their proper close/destroy lifecycle; saved settings can be used to reconstruct presentation, but a cached widget or renderer is not a replacement for a new instance.

Source: `scripts/managers/ui/ui_manager.lua`, `scripts/managers/ui/ui_world_spawner.lua`, `scripts/ui/view_elements/view_element_inventory_weapon_preview/view_element_inventory_weapon_preview.lua`.
