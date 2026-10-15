# Modular props

`PropBody3D` adds attack rules, usable damage stages, destruction, contents, and feedback to `ObjectPhysicsBody3D`. Carrying, anchoring, buoyancy, targeting, and player rebounds are independent settings.

## Examples

- `Objects/Crates/Wood/WoodCrate.tscn`: anchored, non-carryable, command attacks destroy it and emit wooden fragments.
- `Objects/Crates/Wood/CarryableWoodCrate.tscn`: movable and carryable; traversal, command, and sufficiently hard physical impacts can destroy it.
- `Objects/Props/BadnikBounceTarget.tscn`: indestructible homing/magnetism target with a badnik-style rebound and airborne ability refresh.
- `Objects/Carry/CarryableCrate.tscn`: legacy authored crate, upgraded without changing child names or instance overrides. Destruction remains disabled.

The three new examples are beside the carry tests in Niko Test, around world Z 216 and X 18–30. Wood crates there respawn after ten seconds.

## Configuration

Enable **Breakable** for damage stages that leave the object usable. Enable **Destroyable** for terminal removal; fracture output is optional. Both can be enabled for usable stages followed by destruction. Break-only objects retain their final usable state at zero durability.

Add `PropHitRule` entries to **Hit Rules**. The first matching rule applies. An empty list accepts traversal and command attacks. **Blocked Attacks** on the body vetoes every rule. Rule-specific blocked IDs exclude only that rule. Physical impacts require both **Impact Damage Enabled** and a rule accepting Physical Impact. Use normal closing speed thresholds to ignore sliding contacts.

Actions expose **Prop Attack Profiles** for attack IDs, category masks, tags, damage, impulse, and repeat interval. Standard classifications are provided for existing attacks. Spin/Tornado/Uppercut use foot contacts; Bounce/Stomp are command attacks and resolve body contacts before movement, allowing descent through destroyed crates and stacks without landing on them; Jump, Roll, Spindash, Jump Dash, Homing, and Lightspeed Dash are traversal attacks. Neutral movement and defense do not create attacks. Custom attacking actions can set **Prop Body Attack ID** and supply the corresponding profile.

Add `PropDamageStage` entries in descending durability-threshold order. Stages can replace visuals and compound collision, change mass/displacement, emit fragments, or restrict carrying/targeting. Concave replacement shapes are excluded from movable body collision.

Add `PropBounceResponse` entries to configure per-attack and per-outcome rebound behavior. Badnik, radial, and directional responses support speed limits, lateral retention, target motion, jump-held variation, Bounce/Stomp completion, and optional ability refresh. No response is applied by default. **Rearm After Separation** permits reusable bounce targets; profiles can instead specify repeat intervals.

Add one or more `PropTarget3D` markers beneath the body and assign their **Prop** reference when not directly parented. Homing and attack magnetism have independent settings. Target availability respects attack categories unless **Allow Immune Targeting** is enabled. Immune targeting never grants damage eligibility. Carried and destroyed props unregister their targets.

**Contents** uses `PropContent` entries for scene/count/probability/offset/momentum. **Feedback Profiles** uses outcome/attack filters with arrays of sounds and effects. `MetalDestructionFeedback.tres` provides the new metal destruction sound. The wood example uses the new wood sound directly.

## Physics and water

`ObjectPhysicsBody3D` preserves rigid/simplified modes, gravity modifiers, planetary gravity, support/rest logic, surface effects, springs, and carry APIs. `CarryableObject` remains a compatibility adapter through `PropBody3D`, so existing Chao/Aidan scenes gain the same optional capabilities while destruction stays disabled. Carry examples now include dynamic-object collision for stacking. Supplemental motion safety sweeps the actual compound body; **Carry Intangible** defaults on: held bodies disable collision layers/masks and follow the carry target through geometry. Release placement checks the full active compound shape using the saved collision mask, then uses the player’s side-placement fallback when obstructed. Collision filters restore on release, cancellation, destruction, and respawn. Disable **Carry Intangible** to retain obstruction-limited held movement.

Enable **Buoyancy Enabled**, set mass and effective displaced volume, and optionally supply weighted `PropBuoyancySample` entries. Empty arrays generate samples from supported collision shapes. Fluid density × submerged volume × resolved gravity gives lift; mass determines acceleration and weight. Drag follows water-relative velocity, and offset samples produce torque. Simplified mode applies linear buoyancy and drag while retaining its upright policy.

Adventure Water volumes expose density, currents, overlap priority, and an optional fluid-gravity override. Fluid gravity otherwise follows object gravity, including zero gravity. Box boundaries interpolate sample submersion; other volume shapes use containment samples. Rendered texture waves do not alter physical water boundaries.

The shared fracture emitter accepts a source-motion context and additional template-root arrays. Fractures must import as prepared dynamic bodies with convex collision. The emitter reuses those shapes and preserves imported physics by default; it never converts raw meshes or builds collision geometry at runtime. Shared fragments inherit source linear/angular motion and gravity. Live-piece budgets and lifetime/fade settings bound debris cost. Existing enemy defeat effects use this emitter through their existing adapter.

## Validation and current limits

Focused runtime checks are in `LS5Engine3_CodexFiles/prop_system_checks.tscn`. Run with Godot 4.7.2 and the project path. The existing contact, homing re-input, and uppercut checks remain applicable.

Validated: 177 prop assertions, 42 homing re-input assertions, and the existing object-contact and uppercut-fatigue suites pass. A rendered preview verifies intact/fractured wood alignment. Shared, Objects, and Audio export lists include the new dependencies; no executable was rebuilt.

Niko Test also reports pre-existing empty surface-trait arrays serialized as `Array[NodePath]` instead of resource arrays, and a stale Terminal menu UID. These declarations are unchanged by the prop migration. Headless suites retain the project's existing shutdown resource warnings.

Prop hits currently use the existing local-player authority gate. Dedicated multiplayer replication of prop transforms, destruction, contents, and late-join state is not provided by this system. Damage-stage collision changes and respawn changes use deferred collision updates.


## Fragment performance

Fracture collision generation, pivot centering, scale baking, and physics defaults are prepared during import. Runtime spawning duplicates prepared bodies and shares their immutable collision resources. Supplemental sweeps default to a minimum speed of 35 world units per second, independently of native CCD. Intact and carryable body sweeps retain their all-motion default.

Buoyancy collects the water registry once per evaluation and rejects water volumes outside the sample bounds before detailed sampling. Nearby water still uses the same mass, displaced volume, gravity, overlap priority, and torque calculations.

The isolated Niko collision/water benchmark measured one-crate emission at approximately 118 ms before these changes and 4.2 ms afterward; six-crate emission decreased from 713 ms to 15 ms. Ninety-fragment physics averaged approximately 25 ms before and 4.2 ms afterward. Rendering, weather, gameplay scripts, and player input were disabled in this benchmark; these values are not whole-game FPS guarantees. Reproduction scripts and logs are in LS5Engine3_CodexFiles/fracture_performance_*.


## Fracture import workflow

1. In the fracture model's Advanced Import Settings, enable Generate Physics on every piece, choose a Dynamic body, and use a single convex collision shape. Mesh node paths use Godot's sanitized names; dots in source names become underscores.
2. Assign `res://addons/ls5_surface_attach_import/fracture_post_import.gd` as the model's import script.
3. Save a `FractureImportPhysics` resource beside the model named `<model_basename>_physics.tres`. It configures per-piece mass, density, gravity scale, friction, bounce, damping, collision layers, CCD, and safety sweeps. Without a sidecar, the shared defaults apply.
4. Reimport the model after changing its import settings, profile, or import script. The import script rejects meshes missing dynamic bodies or convex shapes and centers each body without moving its rendered mesh.
5. Assign the imported scene as the emitter's fracture source. Leave Override Imported Physics disabled to preserve the profile. Enable it only for an intentional per-emitter variation.

Wood and MonoBeetle models are configured for this workflow. Both use mass 4, gravity scale 4, friction 0.25, bounce 0.15, linear/angular damping 0.09/0.05, collision layer/mask 8/5, CCD, and fast-motion safety sweeps. Wood uses density 600 for buoyancy; MonoBeetle buoyancy is disabled. Templates remain frozen with processing disabled until a copy is emitted. Spawning still instantiates native physics bodies; import-time collision preparation removes geometry-generation stalls rather than guaranteeing zero runtime allocation.

Carry releases retain the player collision exception for the configured release lock and until the active object shapes no longer overlap the releasing player. Attack contacts and physical impact damage from that player are ignored during this guard. World impacts and other attackers retain normal damage behavior.
