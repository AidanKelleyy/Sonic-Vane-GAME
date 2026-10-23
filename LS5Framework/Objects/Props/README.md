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

### Targeted throws

Carried throws preview a reachable homing target while carrying, commit it when the throw begins, and recheck its arc at the animation release frame. Target ranking uses model facing relative to carry up, with angle taking priority over distance. A four-degree switching margin keeps previews stable between nearby targets. Release clearance, target invalidation, and blocked or unreachable arcs retain the ordinary throw or existing side-placement fallback.

Normalized carry animations commit the selected target after the overlay accepts the throw transition and clears the previous release state. Subsequent animation interruptions still cancel that commitment.

Player carry settings control targeting enablement, range, horizontal and vertical angles, flight-time limits, and maximum launch speed relative to inherited player momentum. Defaults are a 24-meter base range, a 90-meter speed-scaled range cap, a 30-degree horizontal half-angle, a 60-degree elevation limit, 0.2–1.6 seconds, and 42 meters per second. Range follows the homing formula: base range plus player speed multiplied by range per speed, clamped to the configured limits. **Carry Throw Target Range Per Speed** defaults to -1, which uses the character's current homing range-per-speed setting; zero restores a fixed range, and a positive value overrides the scaling. Preview, acquisition, and release use the same resolved range. `Thrown Object Targeting Enabled` on homing markers and actor/prop target markers independently disables acquisition.

Rails and their child target markers are always excluded from thrown targeting, including rail beginnings and ends. Their homing registrations and rail-entry behavior remain unchanged.

The solver predicts gravity and damping for both prop simulation modes, including their different gravity integration order. Built-in planetary sources expose a position-sampling API; the solver refines candidate arcs against gravity sampled along their paths, including influence-radius transitions and falloff. Prediction leaves prop transforms unchanged. Arc clearance uses an enclosing sphere around the prop's collision shapes, allowing rotation without reducing clearance. This conservative volume can reject tight openings. Target contact still uses the existing physical impact receivers.

Moving-target lead uses character/body velocity, `get_throw_target_velocity()` when supplied, or sampled target motion for transform-driven markers. Prediction clamps target speed to 40 meters per second by default. Preview searches run at ten physics updates per second. Facing and range checks hide stale previews immediately; committed throws recheck obstruction at the preview rate without switching targets. Visibility respects local authority, HUD visibility, menus, and the throw-reticle toggle; no additional aiming input is required.

Throw previews use `Images/Throw_Reticle.png`; ordinary homing uses `Images/Homing_Reticle.png`. Character texture overrides remain independent. Both 512-pixel icons retain the display size authored for the previous 2000-pixel texture: pixel size is multiplied by reference width divided by actual texture width. **Homing Reticle Reference Width** defaults to 2000 and applies to both icons. Throw tint defaults to white to retain the artwork's colors. The shared acquisition sound and distance scaling remain active.

Actor targets expose their hurtbox's minimum dynamic-impact speed to the throw solver. Candidate arcs retain a 15-percent arrival-speed margin for early volume contact, while launch-speed limits and existing damage thresholds remain unchanged. Hurtboxes recheck slow or cooldown-blocked dynamic contacts only while they overlap, discard pending contacts on separation, and stop assistance on accepted impacts. One accepted overlap is not repeatedly damaged by those pending-contact checks.

Released props can apply limited corrections through `ThrownObjectFlight`. Defaults allow 18 meters per second squared of acceleration and six meters per second of total velocity correction. Flight retains the committed target and ends assistance on impact, pickup, respawn, external kicks or launches, invalid targets, arrival timeout, or target deviation beyond eight meters from the original intercept. Small prediction errors below ten centimeters receive no correction. Assistance preserves normal collision responses and cannot grant damage without contact.

Submerged props retain ordinary throws. Water changes along the flight, Area3D damping overrides, timed directional-gravity modifier expiration, and planetary providers without the position-sampling API remain outside the prediction model. Target acceleration beyond the correction budget can still cause a miss.

`ObjectPhysicsBody3D` preserves rigid/simplified modes, gravity modifiers, planetary gravity, support/rest logic, surface effects, springs, and carry APIs. `CarryableObject` remains a compatibility adapter through `PropBody3D`, so existing Chao/Aidan scenes gain the same optional capabilities while destruction stays disabled. Carry examples now include dynamic-object collision for stacking. Supplemental motion safety sweeps the actual compound body; **Carry Intangible** defaults on: held bodies disable collision layers/masks and follow the carry target through geometry. Release placement checks the full active compound shape using the saved collision mask, then uses the player’s side-placement fallback when obstructed. Collision filters restore on release, cancellation, destruction, and respawn. Disable **Carry Intangible** to retain obstruction-limited held movement.

Simplified props with active collision shapes sweep their complete body and probe the same footprint for support. Collision shapes, offsets, compound parts, and the body's collision mask determine contact; include the dynamic-object layer when authoring stacks. **Simplified Static Friction** holds quiet objects on shallow slopes, while **Simplified Friction** applies time-based sliding resistance. Settled props can support other props; carrying, removing, or moving a support releases the objects above it. Water forces participate in settling, so enabling buoyancy does not keep dry objects awake. Movement and support use object gravity-up. The existing upright policy remains active; shapeless legacy objects retain radius-based fallback checks.

Enable **Buoyancy Enabled**, set mass and effective displaced volume, and optionally supply weighted `PropBuoyancySample` entries. Empty arrays generate samples from supported collision shapes. Fluid density × submerged volume × resolved gravity gives lift; mass determines acceleration and weight. Drag follows water-relative velocity, and offset samples produce torque. Simplified mode applies linear buoyancy and drag while retaining its upright policy.

Adventure Water volumes expose density, currents, overlap priority, and an optional fluid-gravity override. Fluid gravity otherwise follows object gravity, including zero gravity. Box boundaries interpolate sample submersion; other volume shapes use containment samples. Rendered texture waves do not alter physical water boundaries.

The shared fracture emitter accepts a source-motion context and additional template-root arrays. Fractures must import as prepared dynamic bodies with convex or primitive collision. The emitter reuses those shapes and preserves imported physics by default; it never converts raw meshes or builds collision geometry at runtime. Shared fragments inherit source linear/angular motion and gravity. Live-piece budgets and lifetime/fade settings bound debris cost. Existing enemy defeat effects use this emitter through their existing adapter.

## Validation and current limits

Focused runtime checks are in `LS5Engine3_CodexFiles/prop_system_checks.tscn`. Run with Godot 4.7.2 and the project path. The existing contact, homing re-input, and uppercut checks remain applicable.

Throw validation uses `throw_targeting_checks.tscn`, `throw_targeting_advanced_checks.tscn`, `throw_enemy_playtest_checks.tscn`, and `throw_reticle_checks.tscn` in the same folder. The enemy suite throws the authored wood crate at the authored grounded enemy over 8, 16, and 24 meters in both simulation modes. Reticle checks cover texture switching, custom textures, cached and committed previews, and 1280×720, 1920×1080, and 2560×1080 proportions. Run the reticle scene with rendering enabled and `-- --capture-reticles` to save reference screenshots there.

`throw_animation_target_checks.tscn` exercises the normalized carry backend and the native Sonic scene with an actual carry prop. It verifies commitment, preview retention, authored-marker release, aimed launch velocity, flight assistance, grounded targeting, and interruption cancellation.

`throw_speed_target_checks.tscn` covers speed-based acquisition and release, character homing scaling, throw-specific overrides, range caps, and exclusion of actual rails and endpoint markers. The animation suite also tests moving through a throw windup with a target beyond the stationary range.

Validated: 177 prop assertions, 42 homing re-input assertions, and the existing object-contact and uppercut-fatigue suites pass. A rendered preview verifies intact/fractured wood alignment. Shared, Objects, and Audio export lists include the new dependencies; no executable was rebuilt.

Niko Test also reports pre-existing empty surface-trait arrays serialized as `Array[NodePath]` instead of resource arrays, and a stale Terminal menu UID. These declarations are unchanged by the prop migration. Headless suites retain the project's existing shutdown resource warnings.

Prop hits currently use the existing local-player authority gate. Dedicated multiplayer replication of prop transforms, destruction, contents, and late-join state is not provided by this system. Damage-stage collision changes and respawn changes use deferred collision updates.


## Fragment performance

Fracture collision generation, pivot centering, scale baking, and physics defaults are prepared during import. Runtime spawning duplicates prepared bodies and shares their immutable collision resources. Supplemental sweeps default to a minimum speed of 35 world units per second, independently of native CCD. Intact and carryable body sweeps retain their all-motion default.

Buoyancy collects the water registry once per evaluation and rejects water volumes outside the sample bounds before detailed sampling. Nearby water still uses the same mass, displaced volume, gravity, overlap priority, and torque calculations.

The isolated Niko collision/water benchmark measured one-crate emission at approximately 118 ms before these changes and 4.2 ms afterward; six-crate emission decreased from 713 ms to 15 ms. Ninety-fragment physics averaged approximately 25 ms before and 4.2 ms afterward. Rendering, weather, gameplay scripts, and player input were disabled in this benchmark; these values are not whole-game FPS guarantees. Reproduction scripts and logs are in LS5Engine3_CodexFiles/fracture_performance_*.


## Fracture import workflow

1. In the fracture model's Advanced Import Settings, enable Generate Physics on every piece, choose a Dynamic body, and use a single convex shape or a Box, Sphere, Capsule, or Cylinder primitive. Mesh node paths use Godot's sanitized names; dots in source names become underscores.
2. Assign `res://addons/ls5_surface_attach_import/fracture_post_import.gd` as the model's import script.
3. Save a `FractureImportPhysics` resource beside the model named `<model_basename>_physics.tres`. It configures per-piece mass, density, gravity scale, friction, bounce, damping, collision layers, CCD, and safety sweeps. Without a sidecar, the shared defaults apply.
4. Reimport the model after changing its import settings, profile, or import script. The import script rejects meshes missing dynamic bodies or supported collision shapes and centers each body without moving its rendered mesh.
5. Assign the imported scene as the emitter's fracture source. Leave Override Imported Physics disabled to preserve the profile. Enable it only for an intentional per-emitter variation.

Wood and MonoBeetle models are configured for this workflow. Both use mass 4, gravity scale 4, friction 0.25, bounce 0.15, linear/angular damping 0.09/0.05, collision layer/mask 8/5, CCD, and fast-motion safety sweeps. Wood uses density 600 for buoyancy; MonoBeetle buoyancy is disabled. Templates remain frozen with processing disabled until a copy is emitted. Spawning still instantiates native physics bodies; import-time collision preparation removes geometry-generation stalls rather than guaranteeing zero runtime allocation.

Carry releases retain the player collision exception for the configured release lock and until the active object shapes no longer overlap the releasing player. Attack contacts and physical impact damage from that player are ignored during this guard. World impacts and other attackers retain normal damage behavior.

## Local influence benefits

Carrying assigns an influence owner. Releasing or throwing starts a fresh attribution window; an accepted player attack or kick can transfer ownership when its impulse meets **Influence Minimum Impulse**. Anonymous impulses and minor contacts preserve the existing owner without refreshing the window. **Influence Duration** defaults to eight seconds; zero disables expiry. Held ownership does not expire. Respawn/reset and removal of the credited player clear attribution.

`get_score_award_recipient()` exposes the current eligible local beneficiary. Enemy object-impact defeats use it for score, combo credit, and the existing airborne ability refresh, while retaining the impacting object as the damage source. No player bounce is applied for indirect hits. Expired ownership removes benefits without disabling existing enemy impact damage. Attribution is local state and is not replicated online.

Item monitors accept sufficiently fast owned-object impacts. **Object Impact Enabled**, **Object Impact Collision Mask**, and **Object Impact Minimum Speed** configure this behavior; the default speed threshold is 20. Normal closing speed rejects slow and glancing contacts. Touch overlaps handle ordinary contacts, while existing prop collision/sweep callbacks handle solid monitor contacts. Delayed rewards retain the beneficiary selected at impact, including when the object is subsequently influenced by another player. Unowned, expired, held, and ineligible objects do not break monitors. Direct player monitor interactions retain their existing bounce behavior.

Custom local interactions can call `set_influence_owner(player)` or `apply_kick_impulse(impulse, player)`. Existing one-argument impulse calls remain valid. Physical chain ownership propagation and automatic ownership from ordinary walking pushes are not included.

## Ring contents

Add `res://LS5Framework/Objects/Rings/ObjectRingSpew3D.tscn` beneath a prop to emit dropped rings on damage or destruction. The same component works under enemies. Counts, per-life limits, launch speeds, inherited velocity, ring variants, and emission sound are configured on the component. See `Objects/Rings/README.md` for setup and behavior.
