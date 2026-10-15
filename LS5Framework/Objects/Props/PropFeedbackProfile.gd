extends Resource
class_name PropFeedbackProfile

## Sounds selected for matching hit outcomes.
@export var sounds: Array[AudioStream] = []
## Particle or effect scenes spawned for matching outcomes.
@export var effects: Array[PackedScene] = []
## Outcomes producing this feedback.
@export_flags("Rejected", "Damaged", "Broken", "Destroyed") var outcomes: int = 8
## Attack identities accepted by this feedback. Empty accepts all identities.
@export var attacks: Array[StringName] = []
