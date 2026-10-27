@tool
extends Resource
class_name AutomationTrait

enum Channel { STEERING = 1, POSITION = 2, SPEED = 4, SURFACE = 8, INPUT = 16 }

## Enables this resource without removing it from its array.
@export var enabled: bool = true
## Applies while the player has valid ground contact.
@export var grounded: bool = true
## Applies while the player is airborne.
@export var airborne: bool = false


func applies(attached: bool) -> bool:
	return enabled and (grounded if attached else airborne)
