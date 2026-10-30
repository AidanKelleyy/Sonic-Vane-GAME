@tool
extends Resource
class_name LipSyncPose

enum SpeechRole { AUTOMATIC, VOWEL, CLOSURE, CONSONANT, REST, SUSTAINED_CLOSURE, ROUNDED_VOWEL, FRICATIVE }

## Stable pose identifier used by clip timing resources.
@export var id: StringName = &""
## Animation containing the character's facial pose.
@export var animation: Animation
## Text patterns used for transcript draft generation.
@export var spelling_patterns: PackedStringArray = PackedStringArray()
## Draft speech behavior. Automatic recognizes standard viseme IDs; custom poses can specify their sound type.
@export_enum("Automatic", "Vowel", "Lip Closure", "Consonant", "Rest", "Sustained Closure", "Rounded Vowel", "Fricative") var speech_role: int = SpeechRole.AUTOMATIC
## Relative share of speech time allocated to this pose during generation. One uses the sound-type default.
@export_range(0.25, 3.0, 0.05) var generation_duration_scale: float = 1.0
## Speed of approaching this pose during generation. Lower values reach the shape sooner; one uses the sound-type default.
@export_range(0.25, 3.0, 0.05) var generation_attack_scale: float = 1.0
## Relative peak hold during generation, bounded by the clip's Hold Limit. One uses the sound-type default.
@export_range(0.0, 3.0, 0.05) var generation_hold_scale: float = 1.0
## Maximum generated influence for this pose. One uses the sound-type default strength.
@export_range(0.0, 1.0, 0.05) var generation_strength: float = 1.0


func get_speech_role() -> int:
	if speech_role != SpeechRole.AUTOMATIC:
		return speech_role
	if id in [&"VIS_AE", &"VIS_Ah", &"VIS_EE", &"VIS_Ih", &"VIS_Uh"]:
		return SpeechRole.VOWEL
	if id in [&"VIS_Oh", &"VIS_W_OO"]:
		return SpeechRole.ROUNDED_VOWEL
	if id == &"VIS_B_M_P":
		return SpeechRole.CLOSURE
	if id in [&"VIS_F_V", &"VIS_S_Z", &"VIS_Th"]:
		return SpeechRole.FRICATIVE
	if id == &"VIS_SILENT":
		return SpeechRole.REST
	return SpeechRole.CONSONANT

