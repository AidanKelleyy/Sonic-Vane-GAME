# Spatial audio

`SpatialAudioManager` applies shared profiles to every scene-authored or runtime-created `AudioStreamPlayer3D`. Source properties remain available for larger ranges and quieter gains. Profiles raise small attenuation scales and positive cutoffs to the shared minimum; unlimited cutoffs remain unlimited. Reapplying a profile never multiplies its values.

The standard Sonic capsule is approximately 2.03 world units tall. Common running speeds of 145–200 units per second make a 60-unit cutoff shorter than half a second after a launch. The 2.9-second dash panel clip now has a 600-unit cutoff, covering almost three seconds of travel at 200 units per second.

| Profile | Minimum attenuation scale | Minimum positive cutoff | Source ceiling |
| --- | ---: | ---: | ---: |
| World effects | 90 | 320 | −6 dB |
| Character voices | 90 | 360 | −3 dB |
| Launch effects | 120 | 600 | −4 dB |
| Ambience / enemy idle | 60 | 320 | −9 dB |
| Footsteps / movement details | 60 | 240 | −9 dB |

Profiles are stored in `LS5Framework/Resources/Audio/`. Voice bus sources and dialogue players use the voice profile. Dash panels, springs, ramps, rail boosters, and sources playing `DashPanel.wav` use the launch profile. Rain, enemy idle, and ambient sources receive the quieter ambience ceiling. Footstep and slide sources receive the movement-detail ceiling. Other spatial sources use world effects. An optional `spatial_audio_profile` metadata entry accepts a custom `SpatialAudioProfile` resource.

Profiles cap positive pre-attenuation gain at 0 dB, retaining negative gains and fade-outs. This removes extreme authored boosts such as +60 dB without raising quiet sounds. The source ceiling bounds the attenuated output. The SFX, Voice, and Master buses additionally use hard limiters at −4, −3, and −1 dB respectively, bounding overlapping sounds and retaining final output headroom. Existing volume sliders and audio routing remain active.

The policy registers sources when they enter the tree and reapplies after readiness. It checks gain and source ceilings after normal physics updates and refreshes range/profile selection every quarter-second, covering late script configuration. Replicated character voice playback applies the voice profile immediately. Idle actor distance gating uses the effective audio source range and active audio listener, keeping it consistent with the shared policy.

The camera rig's listener follows the tracked player's position, offset one unit along gravity up, while retaining camera orientation for stereo panning. Camera zoom therefore does not change the player's acoustic position. `Audio Listener Player Blend` restores camera-relative positioning at zero or blends between positions. When no target is valid, the listener returns to the camera. The same rig script covers both current and legacy camera scenes. Secondary sun-flare rendering probes keep audio listeners disabled.

The two policy scripts and five profile resources are explicitly selected in Windows, Linux, macOS, and Shared export lists. Both the configured bus layout and the fallback bus layout include the same peak protection.
