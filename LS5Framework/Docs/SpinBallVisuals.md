# Spin Ball visuals

`SpinBallVisuals.gd` is a reusable character visual controller. Neo Adventure Sonic uses the skinned `Armature/Skeleton3D/SpinBall` mesh inside `Sonic_NeoAdventure.glb`. Geometry, UVs, texture, and authored placement remain intact; the controller generates no mesh or material.

## Animation markers

Add `_spinball-enabled=true` to an AnimationNode resource name. Existing arguments can remain in the same resource name, for example:

`_afterimage-speed=true;min_speed=0;max_speed=1;min_alpha=0.765;max_alpha=0.765;_spinball-enabled=true`

The marker reader follows the same active state-machine and selector conditions as after-images. An optional `shear=0.3` argument overrides the controller's shear strength while in a deforming action. `_spinball-enabled=false` suppresses the ball for that route. Neo's Jump, RollFloor, and DropDash nodes are marked in both its embedded tree and authored animation-tree resource.

## Hierarchy

Neo uses `ModelRoot/VisualDeformation/Sonic_NeoAdv_Root`. The SpinBall mesh lives inside the animated model and is referenced through `spin_ball_path`. Its transform and skeleton pose remain animation-controlled. Flicker toggles the other model geometry individually, preserving each mesh's prior visibility, without hiding the model root or skeleton. ModelRoot remains the orientation controller's reference; physics colliders remain outside the deformation layer. Exported animation, skeleton, audio, and other visual node references include the new layer. The imported model hierarchy and animation bone paths are unchanged.

The previous JumpBall instance remains available in the scene, but Neo's player jump_ball reference is empty to avoid overlapping ball systems. Other characters retain their existing JumpBall setup.

## Timing and deformation

The default clock runs at 60 ticks per second, independently of render FPS. The Spin Ball stays hidden for two ticks, then visible for one. Each hidden or visible interval has an 8% chance of lasting one additional tick; holds never stack within an interval. Flicker rate and stutter chance are adjustable in the Inspector. Each character has its own random generator. The model and ball are complementary visibility states, so no blank frame is introduced.

Shear applies during spindash and Drop-Dash charging. Airborne Drop-Dash release clears shear immediately and keeps it disabled until that phase ends. Bounce descent stretches vertically along player gravity-up, independently of visual-root tilt. Rebound clears any residual forward shear before applying vertical squash/stretch. The bottom pivots remain anchored, with sideways scaling compensating for vertical deformation to preserve volume. The shared player visual_bounce_rebounded signal starts a volume-preserving spring beginning with squash, followed by stretch and several diminishing oscillations after bounce landing or enemy/monitor rebound. Deformation returns smoothly to its original transform, and each character has independent visibility, clock, and deformation state while imported geometry and materials remain shared.

Configure flicker frequency, stutter chance, shear, bounce fall stretch, pivot height, response, and rebound duration, strength, and cycle count on the character's SpinBallVisuals node. Reusing the script requires references to the character, AnimationTree, animated visual root, a dedicated deformation root, and a Spin Ball mesh inside the model. Animation controls its SpinBall bone; the controller does not rotate or reset the mesh transform. The default rebound lasts 0.7 seconds with three diminishing cycles.
