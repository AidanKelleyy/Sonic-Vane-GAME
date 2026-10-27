# Modular automation

The modular automation system provides shared path sampling, per-player sessions, and typed movement influences. All seven inventoried levels now use shared automation sources and typed resources. Legacy scene paths and setters remain available for compatibility consumers. The shared evaluator now supports guided movement and terrain-cooperative 2.5D ribbons.

## Source scene

`res://LS5Framework/Objects/Automation/AutomationSplineCore.tscn` supplies the new `AutomationSplineCore` source. Its root is named `AutomationSpline`. The default path runs 30 meters along local negative Z. Capture Distance zero disables distance-based release; finite capture remains the default for new presets. Empty trait arrays preserve normal movement. Add resources directly or instance one of the five scenes under `Objects/Automation/Presets`.

- `Path3D` supplies geometry and canonical curve orientation.
- `Start` and `End` supply endpoint boundary volumes. Their origins define boundary planes perpendicular to the corresponding route tangents. Supported gate shapes are boxes, spheres, capsules, and cylinders. Crossing tests use the body's origin.
- `Volume` supplies ordinary occupancy activation when that mode is selected.

After editing a path, move and size its gates or volume to fit the section. The Automation dock provides undoable generated triggers and a static route preview. Node references resolve relative to the source root and have Inspector descriptions.

Endpoint activation requires an observed signed crossing. Either endpoint can capture inward travel on a bidirectional route; outward travel releases, including backing out through the original entrance. A step through both endpoints captures and releases in crossing order. Spawn and teleport overlap do not count as endpoint entry. Leaving a gate rearms it, and the side deadband prevents a sample exactly on the boundary from discarding crossing history. Disabled/re-enabled sources discard stale crossings.

Occupancy accepts initial overlap and releases through the area's exit signal. Script Only permits explicit registration. Closed curves require Occupancy or Script Only because they have no physical endpoints. Endpoint gates respect their body collision masks; the source also applies its body-group filter.

## Player API

`PlayerController.get_automation_controller()` returns that player's `PlayerAutomationController`. The production player physics callback advances it automatically. Scripted code can call `register_source(source)` and `unregister_source(source.get_instance_id(), reason)`.

`selected` exposes the current `AutomationSession`. `get_session(source)` returns a registered session even while another source supersedes it. Higher source priority wins. Equal priorities use the latest activation sequence; updating an existing registration never changes its activation order. Simultaneous automatic entries are processed in stable scene-path order. Superseded registrations are tracked and revalidated before resuming.

Each session owns its sample, signed speed, travel direction, unwrapped progress, elapsed time, and release reason. Geometry is shared by the source; mutable session state is independent for every player. The canonical tangent and ribbon frame never invert when travel reverses. `session.get_travel_tangent()` returns the canonical tangent multiplied by signed travel direction.

Direction follows signed velocity above the speed deadband. Below that threshold, current movement intent can choose direction; otherwise the previous direction is retained. Endpoint entry supplies the initial fallback. One-way policies reject disallowed entry directions. Input and speed traits control permitted intent, assistance, and automatic propulsion.

`selected_changed(previous, current)` reports ownership changes. `session_released(source_id, reason)` reports releases. Disabling/removing a source, invalidating its curve, and destroying a target clear corresponding sessions. Death and the existing teleport/respawn notification path clear player ownership immediately. Authority/availability loss clears ownership at the next tracking update. Ad hoc transform teleports must use the existing teleport notification path or explicitly clear the controller to suppress swept crossings.

## Shared sampler

`AutomationPathSampler.configure(path)` binds a `Path3D`. `sample(world_distance)` returns a typed `AutomationSample`; `closest(world_position, ...)` finds a route sample using optional progress prediction and a connected local search window. Returned position, distance, and error use world units, including positively scaled and nonuniformly scaled paths.

The cache contains transformed baked points, cumulative world arc lengths, and continuous frames. Curve edits, replacement, and transform changes invalidate it. Ordinary local searches use binary range lookup and examine the nearby segments; the full route is searched only for initial acquisition or permitted recovery. Spatial error, progress continuity, and plausible heading distinguish nearby branches. Full 3D distance is the default. Optional projected queries require an explicit maximum ignored-axis depth.

Frames use orthonormal tangent/up/normal axes, authored up vectors and tilt where enabled, transport through unbanked geometry, and distributed seam closure for closed curves. Open endpoints retain valid one-sided tangents. Tracking uses the baked polyline; bake interval controls geometric accuracy. Ribbon and profile evaluation can apply cubic positions after branch selection through the same world-distance sampler. Distance queries wrap on closed paths, and sessions retain unwrapped progress across forward and reverse seams. Mirrored, singular, empty, and zero-length routes are rejected safely.

Curve3D's baked/up-vector sampling semantics are documented in the [Godot Curve3D reference](https://docs.godotengine.org/en/stable/classes/class_curve3d.html).

## Movement traits

| Array | Resource | Channels |
| --- | --- | --- |
| Steering Traits | `AutomationSteeringTrait` | Input heading and bounded velocity alignment |
| Position Traits | `AutomationPositionTrait` | Free corridor centering, collision-tested confinement, or `AutomationRibbonTrait` depth confinement |
| Speed Traits | `AutomationSpeedTrait` | Input assistance/automatic propulsion, soft cap, maximum-speed override |
| Surface Traits | `AutomationSurfaceTrait` | Grounded correction frame and optional contact adhesion |
| Input Traits | `AutomationInputTrait` | Individual action permissions, breakaway, horizontal/vertical path mapping |
| Transition Traits | `AutomationTransitionTrait` | Independent entry/exit by time or accumulated travel |
| Influence Traits | `AutomationInfluenceTrait` | Per-channel constant, distance, endpoint, progress, speed, and curve factors |
| Camera Traits | `AutomationCameraTrait` | Per-player ribbon companion using the existing camera constraint evaluator |

Each movement resource selects ground and/or airborne eligibility. First applicable entries own each function: one position resource, one drive resource, one cap, one maximum-speed override, one resource per steering/surface mode, one permissions resource, and one path mapping. Invalid overlaps produce configuration warnings. Empty or disabled functions retain normal player behavior.

Influence channels are Steering, Position, Speed, Surface, and Input. The first enabled influence resource assigned to a channel owns its weight. Enabled factors inside that resource multiply; separate resources do not silently multiply together. Zero weight exerts no new movement effect or policy. A held action that was blocked remains disarmed until its input is released, preventing a charge/release or held request from firing on unlock. Latches belong to action IDs, so an allowed jump remains available even when a blocked ability shares its button.

Time transitions use real unpaused seconds; movement forces use the player's movement-clock delta. Distance transitions use accumulated actual route progress, including reverse travel; exit distance uses measured displacement along the retained tangent. Source handoffs ramp incoming continuous assistance from zero while retaining existing physical velocity. Ordinary exits can fade heading, centering acceleration, drive, and soft-cap strength. Input restrictions, adhesion, maximum overrides, and positional confinement release immediately. Death, teleport, disable, removal, breakaway, and invalid paths bypass exit fades.

Speed assistance adds acceleration below its target and preserves faster motion. It is analog-scaled and follows signed input. Propulsion also drives neutral input and suppresses ordinary no-input braking while actually driving; it does not impose a cap. Deliberate pullback can suppress it. Drive and soft-cap resources preserve rolling unless explicitly configured otherwise. Maximum-speed overrides use a separate channel and restore the normal limit on release; existing timed overrides retain precedence.

Corridor centering uses a free radius, spring/damping response, and maximum acceleration. Grounded corrections use the selected surface/gravity/path frame; airborne corrections preserve gravity-up jump motion. Velocity alignment rotates momentum at a bounded rate without changing its magnitude. Confinement resamples after collision movement and limits correction speed. Its correction is tested with the player's collision body before translation. An obstruction can block correction or release the source; it cannot pull the body through the obstacle.

Adhesion only preserves existing valid contact and stops on an intentional jump or detachment. It does not create airborne ground or suppress gravity. Grounded frame changes blend with the Surface channel's influence. Camera-up preferences remain independent.

## Presets

| Scene | Starting behavior |
| --- | --- |
| `SoftRouteGuide.tscn` | Gentle input heading, a wide corridor, normal speed, permitted jump breakaway |
| `LoopAssist.tscn` | Bounded momentum alignment, a narrower corridor, valid-contact adhesion, no speed target |
| `GuidedRun.tscn` | Stronger heading/centering with signed, input-driven speed assistance |
| `ScriptedRun.tscn` | Neutral-input propulsion, collision-tested confinement, selected action restrictions, permitted braking and jump breakaway |
| `SideViewRibbon.tscn` | Bidirectional horizontal path input, terrain-cooperative depth confinement, airborne jumps, side-view camera, normal momentum |

These are editable configurations using one evaluator. Scripted Run permits jumping by default; Block Jump is an explicit opt-in. Every preset is bidirectional. Guided presets use independent entry/exit transition resources; Side View Ribbon uses physical endpoint adherence ramps and its companion camera transition settings.

`PlayerController.is_automation_action_allowed(action_id)` combines the existing legacy permission rules with the modular policy. Common IDs include `jump`, `roll`, `spindash`, `drift`, and individual modular ability IDs. The `actions` ID blocks every action category when listed in Blocked Actions. Existing ability entry points and automatic parkour/ledge/insta-shield checks consult the new policy. New custom direct ability implementations should use the same query.

Jump or lateral breakaway calls `release_source(source, reason)` and prevents immediate recapture. Occupancy sources rearm after leaving their volume; endpoint sources rearm on an outward crossing. Script Only sources can use `rearm_source(source)` explicitly. The permitted jump request is retained.

Exclusive rail, spline-spring, vault, homing, lightspeed, hurt, countdown, and pause/UI states suspend ordinary guidance. Ribbon depth confinement can explicitly continue through homing, lightspeed, and spring alignment; rails, vaults, hurt, countdown, and pause/UI states retain exclusive ownership. During overlap with the legacy automation runtime, legacy movement takes precedence until migration; the two evaluators do not apply competing guidance forces. Existing legacy setters remain available as compatibility entry points; migrated level objects use shared sessions directly.

## 2.5D ribbons and depth profiles

Instance `Presets/SideViewRibbon.tscn`, draw its Path3D, and fit Start/End gates to the route. The ribbon is a typed position resource in Position Traits. Horizontal/vertical path input, permissions, speed assistance, adhesion, and influence/transition resources remain independent. Jump and roll are allowed; drift is blocked by the preset's permissions resource. No propulsion or speed cap is assigned.

The forbidden depth axis can follow the authored path frame, gravity ribbon, player ribbon, or a fixed path axis. Attached terrain adjusts the in-plane tangent while retaining a stable depth axis through full loops. Terrain orientation belongs to each player's session, so reversal does not reverse the canonical frame. Input follows the terrain-adjusted canonical tangent; camera side remains independent of travel direction. Turning slowdown can be suppressed explicitly.

Adaptive centerlines support entry-depth capture, endpoint rebasing, bounded terrain following, and metadata anchors on attached collision pieces or their parents. The default metadata key is `automation_25d_centerline_anchor`: `true` selects node origin, `Vector3` selects a local anchor, and a number supplies a signed depth offset. Profiles take precedence over terrain anchors. Grounded-only adaptation holds profile/anchor depth during jumps unless the selected profile allows airborne following.

Add `AutomationDepthProfile.tscn` under the main route. Its target reference defaults to the parent. Draw its Path3D at the desired depth, then select occupancy, endpoint volumes, or While Target Active. Start/End volumes may lie inside the profile and may contain multiple shapes. Endpoint traversal uses swept box/sphere/capsule/cylinder intersections and directed entry/release roles; it does not toggle ownership on repeated overlap callbacks. Disable Bidirectional Endpoint Areas to preserve dedicated Start-enter/End-release roles. Initial endpoint overlap requires leaving and crossing again. All gates test body origin and respect the collision mask.

Profile selection uses priority, then spatial distance, then scene path for exact ties. Profiles can override centerline response, speed/offset limits, minimum adherence, and position correction settings. Profile branch/activation state belongs to each player's ribbon session and clears with that session. The post-slide refresh does not advance profile response or session timers again.

Ribbon confinement removes only forbidden depth velocity and position error, preserving in-plane jumps and terrain traversal. Position correction is collision-tested, including at full adherence. Maximum correction speed remains effective in the strict core; zero removes the speed bound while retaining collision checks. Obstruction policy can block or release the route. Sideways speed conversion is an explicit opt-in and defaults to zero.

Camera Traits selects the first enabled ribbon companion. Each player receives a separate moving `CameraConstraint` bound to the rig targeting that player. Position/orientation/lens/transitions continue through the existing camera evaluator, including camera priority, suppression/manual look, collision policy, and exit blending. Signed lead reverses smoothly without switching camera side. Idle behavior can recenter or hold the last direction. Camera up uses gravity/player/authored path settings independently of the terrain tangent.

## Authoring tools

The `LS5 Automation Tools` editor plugin is enabled in project settings. Select a modular automation source or its Path3D to use the **Automation** dock. The Inspector's **Open Automation Tools** button raises the dock when it is tabbed behind another panel.

A basic route workflow is:

1. Instance one of the five preset scenes.
2. Shape Path3D with Godot's curve editor.
3. Set trigger width, height, gate depth, and spacing under **Authoring**.
4. Press **Generate / regenerate triggers**.
5. Preview both travel directions, then play and enable the debug overlay or runtime monitor.

**Apply preset behavior** replaces the eight influence arrays, capture distance, and preset integration/sampling options. It retains the authored curve, transforms, priorities, activation mode, and custom node references. **Add Influence** offers readable subtypes, including separate speed assistance/cap and input mapping/permissions choices. Double-click a list entry or use **Edit selected influence** to open the resource Inspector. Up/Down/Remove edit array precedence. **Make selected influence local** and **Make all influences local** duplicate nested configuration resources. Preset application, influence changes, and trigger generation support editor undo/redo.

Generated shapes live under the marked `_AutomationVolumes` subtree. The generator creates canonical endpoint gates and overlapping occupancy boxes following the curve, then updates the source's references. Existing custom areas remain intact. Regeneration replaces only that marked subtree; an unmarked node with the same name blocks generation. Undo restores both geometry and references. Generated boxes use world-space dimensions and a normalized container frame for scaled routes. Regenerate after changing route basis/scale. Generation is capped at 2048 occupancy segments; extreme routes should be split or use authored volumes. Generate endpoints for open routes; closed routes require Occupancy or Script Only activation.

Viewport guides show canonical travel arrows (cyan), corridor/ribbon bounds (purple), forbidden depth axis and preview capture limit (red), physical endpoint ramps (yellow), and the preview cursor/frame (green). Depth profiles show depth links to their target route in orange. Detailed guides appear for the selected route or its descendants; unselected routes retain their centerline. The dock displays canonical distance, signed travel direction/speed, and resolved channel weights. This is a static, grounded, entry-complete preview. It does not simulate terrain contact, captured adaptive offsets, profile activation, or airborne motion; player-up previews use world up. Use the runtime monitor for those states.

Configuration warnings cover invalid curves/transforms, missing activation shapes, empty masks, overlapping influence modes/channels, invalid falloff ranges, and stale generated geometry. Manual volumes remain available through the normal node-reference fields.

## Live editing and runtime diagnostics

Running from the editor debugger enables a separate automation configuration bridge. It sends changed source properties, typed influence resources, nested weight curves, route geometry/tilt, area masks, and supported collision shapes to matching scene instances. Compatible resource edits retain the per-player ribbon/session state. Activation/reference/gate changes release and rearm ownership; an invalid path releases immediately. Geometry updates refresh sampling without applying movement twice. Changes are editor-to-runtime; runtime state is never written back into authored resources.

**Monitor running players** streams session data into the dock. **Debug Overlay Enabled** under Authoring adds an optional per-player read-only overlay during play. Diagnostics include selected source, progress, branch, signed speed/direction, tracking error, channel weights, blocked actions, correction magnitude, obstruction, suspension, and last release reason. Reading diagnostics does not latch or consume input. Overlays use viewport-relative placement, bounded text sizing, and scrolling without taking gameplay focus; they are disabled by default.

## Migrated level content

The migration accounts for 19 original placements as 17 objects: 12 guided routes, three ribbons, and two depth profiles. All seven level scenes retain their scene UIDs, source names/transforms, disabled states, masks, and authored geometry outside the explicit Skyway consolidation. `Objects/Automation/Migration` contains structural bases that retain the original child names/IDs. New content should start from the normal presets.

Guided migrations use canonical heading/propulsion, explicit native soft-cap resources, authored action locks, optional contact adhesion, and speed-scaled Attraction centering. Attraction uses constant/per-speed acceleration and an outer radius falloff. Tangent Damping retains authored lateral damping independently of bounded velocity alignment. Migrated forces run before normal slope response and final speed limits. The Water Bypass surface mode feeds the shared player water-physics query. Optional absolute target-speed curves support authored speed changes along one route.

Area Crossings activation supports authored interior or sibling entrance/exit volumes. Dedicated one-way roles remain available, with swept crossing tests. Effective masks that were previously assigned by legacy `_ready()` are now stored explicitly in level scenes. Curve sampling and immediate release use the shared controller. `Root.maximum_tracking_window` retains authored adaptive-window bounds where present.

Aero Garden's `Objects/AutomationSpline - Skyway` is now one approximately 1967.93 m curve with 11 controls and all three original volume shapes. Overlapping tails are replaced by two tangent-continuous splices. The spiral, return section, endpoint, and authored 540/600 targets remain. A backward terminal handle is aligned with the approach. The consolidated priority is 2; speed blends from 540 to 600 over the first splice. Targets remain subject to each character's normal maximum. The two redundant source nodes are removed and their identities are recorded in the migration audit.

`AutomationMigration.json` records all 862 effective property values, their destinations, original identities, intentional behavior changes, the Skyway splice plan, and all 20 caller classifications. Shipped levels no longer activate the legacy implementations. Compatibility scenes/APIs are retained for external callers and frozen regression fixtures.

## Validation

Run `LS5Engine3_CodexFiles/AutomationSplines/run_phase6.ps1` from PowerShell. The runner first verifies the actual editor plugin, undo/redo, and debugger bridge in an isolated probe, then executes authoring, movement, and foundation regressions, reruns legacy characterization, verifies the frozen phase 1 capture, compares legacy behavior/metrics, and audits export membership. Development fixtures and results remain under `LS5Engine3_CodexFiles/AutomationSplines`.

The editor-only addon is excluded from explicit game-pack lists. The runtime live-edit bridge and optional overlay are included with the other runtime scripts. The runtime scripts are explicitly included in Windows, Linux, macOS, and Objects export lists. The source/depth-profile scenes and five presets belong to the Objects pack. No binary or PCK rebuild is required for editor testing.

Phase 4 verifies Niko Test and Green Hill Canyon fixture geometry, both depth profiles, native terrain anchors/jumps, collision confinement, per-player cameras, camera precedence, and exit blending. The separate broad legacy camera suite previously reported a controller-only mouse-input assertion and stale scene-array diagnostics; those are recorded in the phase report and are outside the targeted phase 4 passing gates.

Phase 5 adds editor/authoring checks and rendered overlay checks at 640×360, 1280×720, and 2560×1080. The actual editor dock and gizmos are also rendered in an isolated project. The migrated placements and Skyway joins are covered by phase 6 checks.

Phase 6 also instantiates all seven complete level scenes and verifies 2,428 unrelated nodes and 1,105 unrelated resources against the pre-migration copies. Niko Test retains 26 pre-existing surface-array assignment diagnostics, reproduced on its pre-migration scene. Full manual gameplay traversal has not been performed.
