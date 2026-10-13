# Character Settings Profiles

Character settings profiles separate physical controls, packaged character defaults, and user overrides.

- Input Map actions `ability_slot_01` through `ability_slot_16` are generic physical slots configured in Controls.
- A `CharacterSettingsProfile` lists the character's modular abilities and default slot assignments.
- User changes are saved to `user://character_profiles.cfg` and do not modify the character package.

## Attributes

`attribute_ids` lists the parameters offered by the character's Attributes tab, in display order. The main menu and pause menu use the same character settings scene. Packaged Sonic Neo Adventure, Adventure Sonic, and Tails profiles expose:

- `visual.outline.enabled`: Enable existing CharacterSurfaceOutline material passes.
- `visual.uekawa.enabled`: Enable existing CharacterUekawaRim material passes.
- `pawn.movement_time_scale`: Base Movement Time Scale, from 0.1x to 1.0x in 0.01 increments. Defaults to the authored pawn value (normally 1.0x); gameplay, debuff, and underwater multipliers remain separate. This physics attribute is locked during races and synchronized online.

Both default to enabled, preserving the character's authored materials. These switches do not add passes to materials that never had them. Filtering duplicates the affected material chains per pawn, preserves unrelated passes, and restores the original chains when re-enabled. Character tinting and the WheelRun cutout remain separate. Race ghosts retain their existing additional-pass suppression.

Eye projection is a required base shader, not an Attribute. Its controller retains ownership of the active material while optional decorative passes are changed behind it. Tinting never substitutes the eye shader. Race ghosts retain an independent eye projector while suppressing their decorative passes.

Additional IDs use:

- `pawn.air_top_speed`: An editable exported pawn property.
- `ability.grounded.run_top_speed`: An ability-owned exported property, selected by its stable `action_id`.
- `ability.parkour.wall_run_kick_upward_sustain_time`: Another modular ability property.
- `visual.hue_overlay_strength`: An exported scalar on the pawn's private visual-profile copy.

Hidden pawn storage fields that mirror modular actions are not editable through `pawn.*`; use the authoritative `ability.*` parameter instead. For scene metadata, an explicitly exported `action_id` is preferred. When absent, the resolver uses the script filename without `_action` or `_ability`. Custom scripts whose initialized ID differs from that name should store their actual `action_id` in the scene.

Boolean, integer, float, enum, and color properties have generated controls. Curves, arrays, resource references, node references, and unsupported IDs produce an unavailable message rather than an unsafe editor. Numeric fields have controller decrement/increment buttons as well as mouse/keyboard entry. Bumpers switch tabs; directional navigation and scrolling remain within the menu.

`attribute_definitions` optionally customizes an ID's `label`, `description`, `category`, `min`, `max`, `step`, `suffix`, and `default`. Export range and enum hints supply the initial constraints. Set explicit player-facing ranges for unrestricted physics parameters. `default_settings` may also supply defaults; those take precedence over the definition default. The original scene value is the fallback.

Example definition:

```gdscript
attribute_ids = [&"ability.grounded.run_top_speed", &"visual.outline.enabled", &"visual.uekawa.enabled"]
attribute_definitions = {
    &"ability.grounded.run_top_speed": {
        "label": "Running Top Speed",
        "category": "Ground Movement",
        "description": "Flat-ground running speed before temporary modifiers.",
        "min": 20.0,
        "max": 200.0,
        "step": 1.0
    }
}
```

Edits are staged until Apply Attributes. Discard and closing without applying do not save edits. Each row has Reset; Reset Attributes stages restoring the tab's defaults without resetting loadouts or routes. Only non-default, validated overrides are saved. `attribute_aliases` maps retired IDs to current IDs when reading prior configuration.

Physics controls are disabled during race countdowns and joined/active races. Presentation attributes remain available. Pawn baselines remain separate from temporary gameplay modifiers. Locally edited settings apply to local playable pawns using that profile, never to remote pawns through the local configuration manager.

Online pawns publish reliable, authority-owned snapshots after local profile changes. Initial authoritative position requests also carry the current attribute snapshot, covering late joins and recreated pawns. Receivers validate the profile namespace, exposed IDs, scalar types, numeric limits, and enum options. Remote values are applied to that pawn only and are never written to local configuration. Only listed attributes are synchronized by this extension; loadout and route customization retain their existing behavior.

## Character package setup

Create a `CharacterSettingsProfile` resource in the character package and set a stable `package_id` and `character_id`. Each ability listed in `ability_catalog` must use the same `ability_id` as its action node's `action_id`.

Each `default_loadout` entry supports:

- `ability_id`: Stable modular action identifier.
- `slot`: Generic Input Map action.
- `gesture`: `press`, `tap`, `hold`, or `release`.
- `hold_time`: Tap window or hold duration in seconds.
- `allow_shared`: Suppresses conflict warnings for intentional shared bindings.
- `modifier_ability_id`: Ability whose assigned slot acts as the hold modifier.
- `modifier_slot`: Fallback modifier slot.
- `modifier_bypasses_hold`: Activates a hold ability immediately while the modifier is held.

List the gestures supported by each ability in its `ability_catalog` definition. The settings menu only offers those activation modes.

Assign the profile to both the character's `CharacterDoc.settings_profile` and the player scene's `character_settings_profile`. The catalog uses the document profile for the menu, while the player scene uses it for runtime input resolution.

## Profile updates

User loadout changes are stored as per-ability overrides. New abilities and updated defaults from a newer character package continue to merge into an existing user profile. Increment `profile_version` when packaged defaults or settings definitions change so migrations can be added without changing the stable profile key.

Character-specific settings can use `default_settings`, `CharacterProfileManager.get_effective_settings()`, and `CharacterProfileManager.set_character_setting()`. These values share the same per-character persistence namespace as the loadout.

## Action routing

`default_routes` defines packaged transitions with stable action identifiers instead of scene paths. User changes and user-created routes are stored with the character profile, so editing a route never modifies or repackages the character.

Set `routes_authoritative` when a character's packaged route list fully replaces its scene-local routes. Leave it disabled for compatibility profiles that still depend on `AbilityRoute` resources or NodePath fallbacks.

Each route supports:

- `route_id`: Stable identifier for merging packaged defaults and user overrides.
- `display_name`: Name shown in the Action Routing menu.
- `source_action`: Action that owns the transition.
- `event`: `ability_triggered`, `input_pressed`, `input_held`, `input_released`, `manual`, `completed`, or `policy`.
- `input_ability`: Ability whose current loadout assignment supplies the input. If omitted, the source action's assignment is used.
- `input_action`: Optional fixed Input Map action for inputs outside the ability slots.
- `target_action`: Stable `action_id` of the routed action.
- `activation`: `execute`, `activate`, `toggle_on`, `neutral_air`, or `clear_active`.
- `required_state`: `any`, `grounded`, or `airborne`.
- `priority`: Evaluation order when more than one route matches.
- `enabled`: Allows packaged routes to be offered as optional behavior.
- `consume_input`: Stops normal action dispatch after a successful input route.
- `block_during_race_countdown`: Prevents the route during the race countdown.
- `allowed_source_actions` and `blocked_source_actions`: Optional source filters used by policies and specialized transitions.

`ability_triggered` evaluates the selected ability's configured gesture and hold window. Raw input events are useful for transitions such as Bounce input release to Stomp. Because `input_ability` resolves through the current loadout, those routes continue to work when the user moves the source ability to another generic slot.

Actions can publish modular lifecycle events with `emit_profile_route_event()`. Spindash publishes `completed` after a normal release. The Sonic and Tails profiles include a disabled `Spindash Completion: Toggle Roll` route that users can enable from Action Routing.

Packaged manual routes retain the identifiers expected by their actions. For example, Spindash requests `spindash_jump`, while Spin Kick requests `coyote_jump` or `no_coyote_jump`. Profiles with matching route IDs are authoritative; the scene-local `AbilityRoute` resources remain as compatibility fallbacks for characters without profile routing.
